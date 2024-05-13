require 'yaml'

module ManageIQ::Providers::Ovirt::InfraManager::OvirtServices
  class Error < StandardError; end
  class VmNotReadyToBoot < Error; end

  class V4
    include Vmdb::Logging

    attr_reader :ext_management_system

    def initialize(args)
      require 'ovirtsdk4'
      @ext_management_system = args[:ems]
    end

    def username_by_href(href)
      ext_management_system.with_provider_connection do |connection|
        user = connection.system_service.users_service.user_service(uuid_from_href(href)).get
        "#{user.name}@#{user.domain.name}"
      end
    end

    def cluster_name_href(href)
      ext_management_system.with_provider_connection do |connection|
        cluster_proxy_from_href(href, connection).name
      end
    end

    # Provisioning
    def get_host_proxy(host, connection)
      connection.system_service.hosts_service.host_service(host.uid_ems)
    end

    def clone_completed?(args)
      source = args[:source]
      phase_context = args[:phase_context]
      logger = args[:logger]

      if source.template?
        vm_clone_completed?(logger, phase_context, source)
      else
        template_clone_completed?(logger, phase_context, source)
      end
    end

    def vm_clone_completed?(logger, phase_context, source)
      source.with_provider_connection do |connection|
        vm = vm_service_by_href(phase_context[:new_vm_ems_ref], connection).get
        status = vm.status
        logger.info("The Vm being cloned is #{status}")
        status == OvirtSDK4::VmStatus::DOWN
      end
    end

    def template_clone_completed?(logger, phase_context, source)
      source.with_provider_connection do |connection|
        template = template_service_by_href(phase_context[:new_vm_ems_ref], connection).get
        status = template.status
        logger.info("The status of the template being cloned is #{status}")
        status == OvirtSDK4::TemplateStatus::OK
      end
    end

    def destination_image_locked?(vm)
      vm.with_provider_object do |vm_proxy|
        vm_proxy.get.status == OvirtSDK4::VmStatus::IMAGE_LOCKED
      end
    end

    def exists_on_provider?(vm)
      vm.with_provider_object do |vm_proxy|
        vm_proxy.get
        true
      end
    rescue OvirtSDK4::Error
      false
    end

    def populate_phase_context(phase_context, vm)
      phase_context[:new_vm_ems_ref] = ManageIQ::Providers::Ovirt::InfraManager.make_ems_ref(vm.href)
    end

    def nics_for_vm(vm)
      vm.with_provider_connection do |connection|
        vm_proxy = connection.system_service.vms_service.vm_service(vm.uid_ems).get
        connection.follow_link(vm_proxy.nics)
      end
    end

    def cluster_find_network_by_name(href, network_name)
      ext_management_system.with_provider_connection do |connection|
        cluster_service = connection.system_service.clusters_service.cluster_service(uuid_from_href(href))
        networks = cluster_service.networks_service.list
        networks.detect { |n| n.name == network_name }
      end
    end

    def configure_vnics(requested_vnics, destination_vnics, destination_cluster, destination_vm)
      destination_vm.with_provider_connection do |connection|
        nics_service = connection.system_service.vms_service.vm_service(destination_vm.uid_ems).nics_service

        requested_vnics.stretch!(destination_vnics).each_with_index do |requested_vnic, idx|
          if requested_vnic.nil?
            nics_service.nic_service(destination_vnics[idx].id).remove
          else
            configure_vnic_with_requested_data("nic#{idx + 1}", requested_vnic, destination_vnics[idx], nics_service, destination_cluster)
          end
        end
      end
    end

    def load_allowed_networks(_hosts, vlans, workflow)
      private_load_allowed_networks(vlans, VmOrTemplate.find(workflow.get_source_vm.id).ems_cluster.uid_ems)
    end

    def filter_allowed_hosts(_workflow, all_hosts)
      all_hosts
    end

    def powered_off_in_provider?(vm)
      vm.with_provider_object { |vm_service| vm_service.get.status } == OvirtSDK4::VmStatus::DOWN
    end

    def powered_on_in_provider?(vm)
      vm.with_provider_object { |vm_service| vm_service.get.status } == OvirtSDK4::VmStatus::UP
    end

    def vm_boot_from_cdrom(operation, name)
      operation.destination.with_provider_object do |vm_service|
        vm_service.start(
          :vm => {
            :os     => {
              :boot => {
                :devices => [OvirtSDK4::BootDevice::CDROM]
              }
            },
            :cdroms => [
              {
                :file => {
                  :id => name
                }
              }
            ]
          }
        )
      end
    rescue OvirtSDK4::Error
      raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::VmNotReadyToBoot
    end

    def detach_floppy(operation)
      operation.destination.with_provider_object do |vm_service|
        vm_service.update(:payloads => [])
      end
    end

    def vm_boot_from_network(operation)
      operation.destination.with_provider_object do |vm_service|
        vm_service.start(
          :vm => {
            :os => {
              :boot => {
                :devices => [
                  OvirtSDK4::BootDevice::NETWORK
                ]
              }
            }
          }
        )
      end
    rescue OvirtSDK4::Error
      raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::VmNotReadyToBoot
    end

    def remote_console_acquire_ticket(vm, userid, originating_server)
      ticket = nil
      rhevm_vm = nil
      vm.with_provider_object do |vm_service|
        ticket = vm_service.ticket
        rhevm_vm = vm_service.get
      end

      SystemConsole.force_vm_invalid_token(vm.id)
      console_args = {
        :user       => User.find_by(:userid => userid),
        :vm_id      => vm.id,
        :protocol   => rhevm_vm.display.type,
        :secret     => ticket.value,
        :url_secret => SecureRandom.hex,
        :ssl        => rhevm_vm.display.secure_port.present?
      }
      host_address = rhevm_vm.display.address
      host_port    = rhevm_vm.display.secure_port || rhevm_vm.display.port

      SystemConsole.launch_proxy_if_not_local(console_args, originating_server, host_address, host_port)
    end

    def native_console_connection(vm)
      vm.with_provider_object do |vm_service|
        consoles = vm_service.graphics_consoles_service.list(:current => true)
        return nil if consoles.empty?

        console = select_graphics_console(consoles)
        Base64.encode64(vm_service.graphics_consoles_service.console_service(console.id).remote_viewer_connection_file)
      end
    end

    def get_template_proxy(template, connection)
      TemplateProxyDecorator.new(
        connection.system_service.templates_service.template_service(template.uid_ems),
        connection,
        self
      )
    end

    def get_vm_proxy(vm, connection)
      VmProxyDecorator.new(connection.system_service.vms_service.vm_service(vm.uid_ems), connection, self)
    end

    def collect_disks_by_hrefs(disks)
      vm_disks = []
      ext_management_system.with_provider_connection do |connection|
        disks.each do |disk|
          parts = URI(disk).path.split('/')
          begin
            vm_disks << connection.system_service.storage_domains_service.storage_domain_service(parts[2]).disks_service.disk_service(parts[4]).get
          rescue OvirtSDK4::Error
            nil
          end
        end
      end
      vm_disks
    end

    def shutdown_guest(operation)
      operation.with_provider_object(&:shutdown)
    rescue OvirtSDK4::Error => err
      _log.error("Error while doing shutdown_guest: #{err}")
    end

    def reboot_guest(operation)
      operation.with_provider_object(&:reboot)
    rescue OvirtSDK4::Error => err
      _log.error("Error while doing reboot guest: #{err}")
    end

    def start_clone(source, clone_options, phase_context)
      source.with_provider_object do |rhevm_template|
        vm = rhevm_template.create_vm(clone_options)
        populate_phase_context(phase_context, vm)
      end
    end

    def make_template(source, clone_options, phase_context)
      source.with_provider_object do |rhevm_vm|
        template = rhevm_vm.make_template(clone_options)
        populate_phase_context(phase_context, template)
      end
    end

    def vm_start(vm, opts = {})
      vm.with_provider_object do |rhevm_vm|
        rhevm_vm.start(opts)
      end
    rescue OvirtSDK4::Error => err
      _log.error("Error starting vm: #{err}")
    end

    def vm_stop(vm)
      vm.with_provider_object(&:stop)
    rescue OvirtSDK4::Error => err
      _log.error("Error stopping vm: #{err}")
    end

    def vm_suspend(vm)
      vm.with_provider_object(&:suspend)
    end

    def vm_reconfigure(vm, options = {})
      log_header = "EMS: [#{ext_management_system.name}] #{vm.class.name}: id [#{vm.id}], name [#{vm.name}], ems_ref [#{vm.ems_ref}]"
      spec = options[:spec]

      _log.info("#{log_header} Started...")

      vm.with_provider_object do |vm_service|
        # Retrieve the current representation of the virtual machine:
        # mandatory for memory parameters and to check if next_run_configuration_exists

        vm = vm_service.get(:all_content => true)
        new_vm_specs = {}

        # Update the memory:
        memory = spec['memoryMB']
        new_vm_specs.merge!(new_vm_memory_specs(vm, memory.megabytes)) if memory

        # Update the CPU:
        cpu_total = spec['numCPUs']
        cpu_cores = spec['numCoresPerSocket']
        cpu_sockets = cpu_total / (cpu_cores || vm.cpu.topology.cores) if cpu_total
        new_vm_specs.merge!(new_vm_cpu_specs(cpu_cores, cpu_sockets)) if cpu_cores || cpu_sockets

        unless new_vm_specs.empty?
          vm_service.update(
            OvirtSDK4::Vm.new(
              new_vm_specs
            ),
            :next_run => vm.next_run_configuration_exists
          )
        end

        # Remove disks:
        removed_disk_specs = spec['disksRemove']
        remove_vm_disks(vm_service, removed_disk_specs) if removed_disk_specs

        # Add disks:
        added_disk_specs = spec['disksAdd']
        if added_disk_specs
          added_disk_specs[:default] = {}
          added_disk_specs[:default][:interface] = 'virtio_scsi' if vm.virtio_scsi.enabled
          add_vm_disks(vm_service, added_disk_specs)
        end

        edit_disk_specs = spec['disksEdit']
        if edit_disk_specs
          edit_vm_disks(vm_service, edit_disk_specs)
        end

        network_specs = spec['networkAdapters']
        if network_specs
          network_specs.each do |action, nets|
            send("#{action}_vm_networks", nets, vm_service)
          end
        end
      end

      _log.info("#{log_header} Completed.")
    end

    def advertised_images
      ext_management_system.with_provider_connection do |ems_service|
        query = { :search => "status=#{OvirtSDK4::DataCenterStatus::UP}" }
        data_centers = ems_service.system_service.data_centers_service.list(:query => query)
        iso_sd = nil
        data_centers.each do |dc|
          iso_sd = ems_service.follow_link(dc.storage_domains).detect do |sd|
            sd.type == OvirtSDK4::StorageDomainType::ISO && sd.status == OvirtSDK4::StorageDomainStatus::ACTIVE
          end
          break iso_sd if iso_sd
        end
        return [] unless iso_sd

        sd_service = ems_service.system_service.storage_domains_service.storage_domain_service(iso_sd.id)
        iso_images = sd_service.files_service.list

        iso_images
      end
    rescue OvirtSDK4::Error => err
      name = ext_management_system.try(:name)
      _log.error("Error Getting ISO Images on ISO Datastore on Management System <#{name}>: #{err.class.name}: #{err}")
      raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error, err
    end

    def host_activate(host)
      host.with_provider_object(&:activate)
    end

    def host_deactivate(host)
      host.with_provider_object(&:deactivate)
    end

    class VmProxyDecorator < SimpleDelegator
      attr_reader :ovirt_services, :connection

      def initialize(vm_service, connection, ovirt_services)
        @obj = vm_service
        @connection = connection
        @ovirt_services = ovirt_services
        super(vm_service)
      end

      def update_memory_reserve!(memory_reserve_size)
        vm = get
        vm.memory_policy.guaranteed = memory_reserve_size
        update(vm)
      end

      def update_description!(description)
        vm = get
        vm.description = description
        update(vm)
      end

      def update_memory!(memory, limit)
        vm = get
        vm.memory = memory unless memory.zero?
        vm.memory_policy.max = limit unless limit.zero?
        update(vm)
      end

      def update_host_affinity!(dest_host_ems_ref)
        vm = get
        vm.placement_policy.hosts = [OvirtSDK4::Host.new(:id => ovirt_services.uuid_from_href(dest_host_ems_ref))]
        update(vm)
      end

      def update_cpu_topology!(cpu_hash)
        vm = get
        vm.cpu.topology = OvirtSDK4::CpuTopology.new(cpu_hash)
        update(vm)
      end

      def attach_floppy(filename_hash)
        name, content = filename_hash.first
        file = OvirtSDK4::File.new(:name => name, :content => content)
        payload = OvirtSDK4::Payload.new(:files => [file], :type => "floppy")
        vm = get
        vm.payloads ||= []
        vm.payloads << payload
        update(vm)
      end

      #
      # Updates the `initialization` of the virtual machine using the given custom script.
      #
      # @param content [String] YAML text containing the cloud-init configuration.
      #
      def update_cloud_init!(content)
        # Do nothing if the cloud-init configuration is empty or nil:
        return if content.blank?

        # When this was implemented using version 3 of the API some of the attributes of the
        # initialization object were directly copied from the YAML text, ignoring the syntax of the
        # cloud-init files. For example, we expected to have a YAML file like this:
        #
        #   host_name: myvm.example.com
        #   user_name: root
        #   root_password: mypass
        #   ...
        #
        # These are *not* part of the syntax supported by cloud-init, but just values that we used
        # to copy to the initialization object. To preserve backwards compatibility, and to support
        # the existing customization scripts, we need to use the same logic that the 'ovirt' gem
        # used to extract these values. For more details see 'cloud_init=' and
        # 'converted_cloud_init' methods in the 'vm.rb' file of the 'ovirt' gem.
        #
        # This is the list of keys that need special treatment:
        keys = %i[
          active_directory_ou
          authorized_ssh_keys
          dns_search
          dns_servers
          domain
          host_name
          input_locale
          nic_configurations
          org_name
          regenerate_ssh_keys
          root_password
          system_locale
          timezone
          ui_language
          user_locale
          user_name
        ]

        # Load the YAML text and check it is a hash, as otherwise we will not be able to process it
        # and cloud-init will not understand it either.
        yaml = YAML.safe_load(content)
        unless yaml.kind_of?(Hash)
          message = \
            "The cloud-init configuration '#{content}' can't be parsed as hash;" \
            "cloud-init would not understand it"
          raise MiqException::MiqProvisionError, message
        end

        # Remove from the YAML the keys that need special treatment, and add them to the hash that
        # will be used to create the initialization object.
        hash = {}
        keys.each do |key|
          value = yaml.delete(key.to_s)
          hash[key] = value if value
        end

        # The SDK expects a hash where keys are symbols, but we may have strings inside nested
        # hashes, for example for NIC configurations, so we need to convert them to symbols:
        hash = hash.deep_symbolize_keys

        # Convert the remaining YAML back to text, removing the initial '---' line that the dump
        # method adds, as cloud-init does not understand it. The result will be used as the custom
        # cloud-init script.
        unless yaml.empty?
          script = YAML.dump(yaml)
          script.sub!(/^---\n/, '')
          hash[:custom_script] = script
        end

        # Send the update to the server:
        update(
          OvirtSDK4::Vm.new(
            :initialization => hash
          )
        )
      end

      def make_template(options)
        templates_service = connection.system_service.templates_service
        cluster = ovirt_services.cluster_from_href(options[:cluster], connection)
        if options[:storage]
          storage = ovirt_services.storage_from_href(options[:storage], connection)
        end
        vm = get
        vm.disk_attachments = connection.follow_link(vm.disk_attachments)
        template = build_template_from_hash(:name        => options[:name],
                                            :vm          => vm,
                                            :description => options[:description],
                                            :cluster     => cluster,
                                            :storage     => storage)
        templates_service.add(template, :seal => options[:seal])
      end

      def build_template_from_hash(args)
        options = {
          :name           => args[:name],
          :description    => args[:description],
          :vm             => args[:vm],
          :cluster        => args[:cluster],
          :storage_domain => args[:storage] && {:id => args[:storage].id}
        }.compact
        OvirtSDK4::Template.new(options)
      end

      def update_sysprep!(content)
        update(
          OvirtSDK4::Vm.new(
            :initialization => {
              :custom_script => content
            }
          )
        )
      end

      def destroy
        remove
      end

      def unregister
        remove(:detach_only => true)
      end
    end

    class TemplateProxyDecorator < SimpleDelegator
      attr_reader :connection, :ovirt_services
      def initialize(template_service, connection, ovirt_services)
        @obj = template_service
        @connection = connection
        @ovirt_services = ovirt_services
        super(template_service)
      end

      def create_vm(options)
        return create_skeletal_vm(options) if options[:clone_type] == :skeletal

        create_cloned_vm(options)
      end

      def create_cloned_vm(options)
        vms_service = connection.system_service.vms_service
        cluster = ovirt_services.cluster_from_href(options[:cluster], connection)
        template = get
        clone = options[:clone_type] == :full
        disk_attachments = build_disk_attachments(template, options[:sparse], options[:storage], options[:name], options[:disk_format])
        vm = build_vm_from_hash(:name             => options[:name],
                                :template         => template,
                                :cluster          => cluster,
                                :disk_attachments => disk_attachments)
        vms_service.add(vm, :clone => clone)
      end

      def create_skeletal_vm(options)
        vms_service = connection.system_service.vms_service
        cluster = ovirt_services.cluster_from_href(options[:cluster], connection)
        template = get
        vm = build_vm_from_hash(:name     => options[:name],
                                :template => blank_template_sdk_obj,
                                :cluster  => cluster)
        vm_res = vms_service.add(vm, :clone => false)
        add_disk_attachments_to_vm(template, vm_res, vms_service, options)
        vm_res
      end

      def blank_template_sdk_obj
        connection.system_service.templates_service.template_service("00000000-0000-0000-0000-000000000000").get
      end

      def add_disk_attachments_to_vm(template, vm_res, vms_service, options)
        disk_attachments = build_skeletal_disk_attachments(template, options[:sparse], options[:storage], options[:name], options[:disk_format])
        disk_attachments_service = vms_service.vm_service(vm_res.id).disk_attachments_service
        disk_attachments.each do |disk_attachment|
          disk_attachments_service.add(disk_attachment)
        end
      end

      def build_skeletal_disk_attachments(template, sparse, storage_href, vm_name, disk_format)
        disk_attachments = connection.follow_link(template.disk_attachments)
        apply_full_disk_details_on_diks_attachments(disk_attachments)
        apply_sparsity_on_disk_attachments(disk_attachments, sparse, disk_format) unless sparse.nil?
        apply_storage_domain_on_disk_attachments(disk_attachments, storage_href) unless storage_href.nil?
        apply_name_on_disk_attachments(disk_attachments, vm_name)
        nullify_disk_ids(disk_attachments)
        disk_attachments
      end

      def nullify_disk_ids(disk_attachments)
        disk_attachments.each do |disk_attachment|
          disk_attachment.disk.href = nil
          disk_attachment.disk.id = nil
        end
      end

      def apply_full_disk_details_on_diks_attachments(disk_attachments)
        disk_attachments.each do |disk_attachment|
          current_disk = disk_attachment.disk
          disk = connection.system_service.disks_service.disk_service(current_disk.id).get
          disk_attachment.disk = disk
        end
      end

      def build_disk_attachments(template, sparse, storage_href, vm_name, disk_format)
        disk_attachments = connection.follow_link(template.disk_attachments)
        apply_sparsity_on_disk_attachments(disk_attachments, sparse, disk_format) unless sparse.nil?
        apply_storage_domain_on_disk_attachments(disk_attachments, storage_href) unless storage_href.nil?
        apply_name_on_disk_attachments(disk_attachments, vm_name)
        disk_attachments
      end

      def apply_name_on_disk_attachments(disk_attachments, vm_name)
        disk_attachments.each_with_index { |disk_attachment, index| disk_attachment.disk.name = "#{vm_name}_Disk#{index + 1}" }
      end

      def apply_storage_domain_on_disk_attachments(disk_attachments, storage_href)
        return if storage_href.nil?

        storage_domain = ovirt_services.storage_from_href(storage_href, connection)
        disk_attachments.each do |disk_attachment|
          disk_attachment.disk.storage_domains = [storage_domain]
        end
      end

      def apply_sparsity_on_disk_attachments(disk_attachments, sparse, disk_format)
        return if sparse.nil?

        disk_attachments.each do |disk_attachment|
          disk_attachment.disk.format = disk_format
          disk_attachment.disk.sparse = sparse
        end
      end

      def build_vm_from_hash(args)
        vm_options = {
          :name             => args[:name],
          :template         => args[:template],
          :cluster          => args[:cluster],
          :disk_attachments => args[:disk_attachments]
        }.compact
        OvirtSDK4::Vm.new(vm_options)
      end
    end

    def cluster_from_href(href, connection)
      connection.system_service.clusters_service.cluster_service(uuid_from_href(href)).get
    end

    def storage_from_href(href, connection)
      connection.system_service.storage_domains_service.storage_domain_service(uuid_from_href(href)).get
    end

    def uuid_from_href(ems_ref)
      URI(ems_ref).path.split('/').last
    end

    def get_mac_address_of_nic_on_requested_vlan(args)
      vm = args[:destination]
      nics = nics_for_vm(vm)
      find_mac_address_on_network(nics, args[:value_of_vlan_option], vm.uid_ems)
    end

    def find_mac_address_on_network(nics, vnic_profile_id, uid_ems)
      vnic_profile_id = parse_vnic_profile_id(vnic_profile_id, uid_ems)
      nic = if vnic_profile_id == '<Empty>'
              nics.detect do |n|
                n.vnic_profile.nil?
              end
            elsif vnic_profile_id == '<Template>'
              nics.first
            else
              nics.detect do |n|
                n.vnic_profile.id == vnic_profile_id
              end
            end

      if nics.empty?
        _log.warn("Cannot find a MAC address, there are no NICs")
      elsif nic.nil?
        _log.warn("Cannot find a MAC address based on vnic_profile=#{vnic_profile_id}, there is no NIC with this profile")
      end

      nic&.mac&.address
    end

    def event_fetcher
      ManageIQ::Providers::Ovirt::InfraManager::EventFetcher.new(ext_management_system)
    end

    def collect_external_network_providers
      ext_management_system.with_provider_connection do |connection|
        connection.system_service.openstack_network_providers_service.list
      end
    end

    private

    def select_graphics_console(consoles)
      # In case of multiple graphics console ('SPICE + VNC') choose the SPICE one
      pref_type = 'spice'
      console = consoles.find { |c| c.protocol.downcase == pref_type }

      unless console
        console = consoles.first
        _log.warn("Can't find a console of type #{pref_type}, choosing a #{console.protocol} type one")
      end
      console
    end

    #
    # Hot plug of virtual memory has to be done in quanta of this size. Actually this is configurable in the
    # engine, using the `HotPlugMemoryMultiplicationSizeMb` configuration parameter, but it is very unlikely
    # that it will change.
    #
    HOT_PLUG_DIMM_SIZE = 256.megabyte.freeze

    def cluster_proxy_from_href(href, connection)
      connection.system_service.clusters_service.cluster_service(uuid_from_href(href)).get
    end

    def vm_service_by_href(href, connection)
      vm_uuid = uuid_from_href(href)
      connection.system_service.vms_service.vm_service(vm_uuid)
    end

    def template_service_by_href(href, connection)
      template_uuid = uuid_from_href(href)
      connection.system_service.templates_service.template_service(template_uuid)
    end

    def new_vm_cpu_specs(cpu_cores, cpu_sockets)
      {
        :cpu => {
          :topology => {
            :cores   => cpu_cores,
            :sockets => cpu_sockets
          }
        }
      }
    end

    #
    # Updates the amount memory of a virtual machine.
    #
    # @param vm [OvirtSDK4::Vm] The current representation of the virtual machine.
    # @param memory [Integer] The new amount of memory requested by the user.
    # @return [Hash] the new memory specs
    #
    def new_vm_memory_specs(vm, memory)
      # Calculate the adjusted virtual and guaranteed memory:
      virtual = calculate_adjusted_virtual_memory(vm, memory)
      guaranteed = calculate_adjusted_guaranteed_memory(vm, memory)

      # The required memory cannot exceed the max configured memory of the VM. Therefore, we'll increase the max
      # memory up to 1TB or to the required limit, to allow a successful update for the VM.
      # Once 'max' memory attribute will be introduced, this code should be replaced with the specified max memory.
      supports_max = ext_management_system.version_at_least?('4.1')
      max = calculate_max_memory(vm, memory) if supports_max

      {
        :memory        => virtual,
        :memory_policy => {
          :guaranteed => guaranteed,
          :max        => (max if supports_max)
        }.compact
      }
    end

    #
    # Adjusts the new requested virtual memory of a virtual machine so that it satisfies the constraints imposed
    # by the engine.
    #
    # @param vm [OvirtSDK4::Vm] The current representation of the virtual machine.
    # @param memory [Integer] The new amount of memory requested by the user.
    # @return [Integer] The amount of memory requested by the user adjusted so that it satisfies the constrains
    #   imposed by the engine.
    #
    def calculate_adjusted_virtual_memory(vm, memory)
      # Initially there is no need for adjustment:
      adjusted = memory

      # If the virtual machine is running then the difference in memory has to be a multiple of 256 MiB, otherwise
      # the engine will not perform the hot plug of the new memory. The reason for this is that hot plugging of
      # memory is performed adding a new virtual DIMM to the virtual machine, and the size of the virtual DIMM
      # is 256 MiB. This means that we need to round the difference up to the closest multiple of 256 MiB.
      if vm.status == OvirtSDK4::VmStatus::UP
        delta = memory - vm.memory
        remainder = delta % HOT_PLUG_DIMM_SIZE
        if remainder.positive?
          adjustment = HOT_PLUG_DIMM_SIZE - remainder
          adjusted = memory + adjustment
          _log.info(
            "The change in virtual memory of virtual machine '#{vm.name}' needs to be a multiple of " \
            "#{HOT_PLUG_DIMM_SIZE / 1.megabyte} MiB, so it will be adjusted to #{adjusted / 1.megabyte} MiB."
          )
        end
      end

      # Return the adjusted memory:
      adjusted
    end

    #
    # Adjusts the guaranteed memory of a virtual machine so that it satisfies the constraints imposed by the
    # engine.
    #
    # @param vm [OvirtSDK4::Vm] The current representation of the virtual machine.
    # @param memory [Integer] The new amount of memory requested by the user (and maybe already adjusted).
    # @return [Integer] The amount of guaranteed memory to request so that it satisfies the constraints imposed by
    #   the engine.
    #
    def calculate_adjusted_guaranteed_memory(vm, memory)
      # Get the current amount of guaranteed memory:
      current = vm.memory_policy.guaranteed

      # Initially there is no need for adjustment:
      adjusted = current

      # The engine requires that the virtual memory is bigger or equal than the guaranteed memory at any given
      # time. Therefore, we need to adjust the guaranteed memory so that it is the minimum of the previous
      # guaranteed memory and the new virtual memory.
      if current > memory
        adjusted = memory
        _log.info(
          "The guaranteed physical memory of virtual machine '#{vm.name}' needs to be less or equal than the " \
          "virtual memory, so it will be adjusted to #{adjusted / 1.megabyte} MiB."
        )
      end

      # Return the adjusted guaranteed memory:
      adjusted
    end

    #
    # Adjusts the max memory of a virtual machine so that it satisfies the constraints imposed by the
    # engine. The max memory is supported since version 4.1 and limited to 1TB according to the UI limits
    # defined for ovirt provider.
    #
    # @param vm [OvirtSDK4::Vm] The current representation of the virtual machine.
    # @param memory [Integer] The new amount of memory requested by the user.
    # @return [Integer] The amount of max memory to request so that it satisfies the constraints imposed by
    #   the engine.
    #
    def calculate_max_memory(vm, memory)
      max = vm.memory_policy&.max || memory
      if memory >= 1.terabyte
        max = memory
      elsif memory > max
        max = [memory * 4, 1.terabyte].min
      end

      max
    end

    def edit_vm_disks(vm_service, disks_specs)
      disk_attachments_service = vm_service.disk_attachments_service
      disks_specs.each do |d|
        das = disk_attachments_service.attachment_service(d[:disk_name])
        das.update(:disk => {:provisioned_size => d[:disk_size_in_mb].megabytes})
      rescue OvirtSDK4::NotFoundError => err
        err_msg = "No disk with the id [#{d[:disk_name]}] is attached to the vm"

        _log.error("#{err_msg} | #{err}")
        raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error, err_msg
      rescue OvirtSDK4::Error => err
        err_msg = "Error resizing disk with the id [#{d[:disk_name]}]. #{err.fault&.detail}"

        _log.error("#{err_msg} | #{err}")
        raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error, err_msg
      end
    end

    #
    # Adds disks to a virtual machine.
    #
    # @param vm_service [OvirtSDK4::VmsService] The service that manages the virtual machine.
    # @param disk_specs [Hash] The specification of the disks to add.
    #
    def add_vm_disks(vm_service, disk_specs)
      storage_spec = disk_specs[:storage]
      default_disk_spec = disk_specs[:default] || {}
      attachments_service = vm_service.disk_attachments_service
      disk_specs[:disks].each do |disk_spec|
        attachment = prepare_vm_disk_attachment(default_disk_spec.merge(disk_spec), storage_spec)
        attachments_service.add(attachment)
      end
    end

    #
    # Prepares a disk attachment for adding a new disk to a virtual machine.
    #
    # @param disk_spec [Hash] The specification of the disk to add.
    # @param storage_spec [Hash] The specification of the storage to use.
    #
    def prepare_vm_disk_attachment(disk_spec, storage_spec)
      disk_spec = disk_spec.symbolize_keys
      attachment_builder = ManageIQ::Providers::Ovirt::InfraManager::DiskAttachmentBuilder.new(
        :size_in_mb       => disk_spec[:disk_size_in_mb],
        :storage          => storage_spec,
        :name             => disk_spec[:disk_name],
        :thin_provisioned => disk_spec[:thin_provisioned],
        :bootable         => disk_spec[:bootable],
        :interface        => disk_spec[:interface]
      )
      attachment_builder.disk_attachment
    end

    #
    # Removes disks from a virtual machine.
    #
    # @param vm_service [OvirtSDK4::VmsService] The service that manages the virtual machine.
    # @param disk_specs [Array<Hash>] The specifications of the disks to remove.
    #
    # TODO: Note that disk_spec['disk_name'] is actually the disks id not its name.
    # we should change that because it is very confusing.
    def remove_vm_disks(vm_service, disk_specs)
      attachments_service = vm_service.disk_attachments_service
      disk_specs.each do |disk_spec|
        disk_spec = disk_spec.with_indifferent_access
        attachment_service = attachments_service.attachment_service(disk_spec['disk_name'])
        attachment_service.remove(:detach_only => !disk_spec['delete_backing'])
      rescue OvirtSDK4::NotFoundError
        raise "no disk with the id #{disk_spec['disk_name']} is attached to the vm: #{vm_service.get.name}"
      rescue OvirtSDK4::Error
        raise "Failed to detach disk with the id #{disk_spec['disk_name']} from the vm: #{vm_service.get.name}, check that it exists"
      end
    end

    def add_vm_networks(networks, vm_service)
      nics_service = vm_service.nics_service
      with_each_network(networks) do |n|
        configure_vnic(
          :nic_name     => n[:name],
          :vnic_profile => n[:vnic_profile_id],
          :nics_service => nics_service,
          :logger       => _log
        )
      end
    end

    def edit_vm_networks(networks, vm_service)
      nics_service = vm_service.nics_service

      with_each_network(networks) do |n|
        vnic = Struct.new(:id).new(n[:nic_id])
        nic_service = nics_service.nic_service(vnic.id)
        nic_service.deactivate
        configure_vnic(
          :nic_name     => n[:name],
          :vnic_profile => n[:vnic_profile_id],
          :nics_service => nics_service,
          :vnic         => vnic,
          :logger       => _log
        )
        nic_service.activate
      end
    end

    def remove_vm_networks(networks, vm_service)
      with_each_network(networks) do |n|
        nic_service = vm_service.nics_service.nic_service(n[:nic_id])
        nic_service.deactivate
        nic_service.remove
      end
    end

    def with_each_network(networks)
      networks.each do |n|
        yield n
      rescue OvirtSDK4::NotFoundError => err
        err_msg = "Error reconfiguring [#{n[:name]}]. NIC not found"

        _log.error("#{err_msg} | #{err}")
        raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error, err_msg
      rescue OvirtSDK4::Error => err
        err_msg = "Error reconfiguring [#{n[:name]}]. #{err.fault&.detail}"

        _log.error("#{err_msg} | #{err}")
        raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error, err_msg
      end
    end

    def configure_vnic_with_requested_data(name, requested_vnic, destination_vnic, nics_service, destination_cluster)
      requested_profile_id = parse_vnic_profile_id(requested_vnic[:network], destination_cluster.uid_ems)
      if requested_profile_id == '<Empty>'
        profile_id = nil
      else
        vnic_profile = find_vnic_profile_in_cluster(requested_profile_id, destination_cluster.uid_ems)
        if vnic_profile.nil?
          raise MiqException::MiqProvisionError, "Unable to find specified profile: <#{requested_profile_id}>"
        else
          profile_id = vnic_profile[0].id
        end
      end

      configure_vnic(
        :mac_addr     => requested_vnic[:mac_address],
        :vnic_profile => profile_id,
        :nic_name     => name,
        :interface    => requested_vnic[:interface],
        :vnic         => destination_vnic,
        :nics_service => nics_service,
        :logger       => _log
      )
    end

    # TODO: @borod108 consider if we can get this from local as well during provisioning
    def private_load_allowed_networks_from_provider(vlans, uid_ems_cluster)
      profiles = get_vnic_profiles_in_cluster(uid_ems_cluster)
      profiles.each do |profile, profile_network|
        vlans[profile.id] = "#{profile.name} (#{profile_network.name})"
      end

      vlans['<Empty>'] = _('<No Profile>')
      vlans['<Template>'] = _('<Use template nics>')
    end

    def private_load_allowed_networks(vlans, uid_ems_cluster)
      profiles = local_get_vnic_profiles_in_cluster(uid_ems_cluster)
      profiles.merge!(local_external_vnic_profiles(uid_ems_cluster))
      profiles.each do |profile, profile_network|
        vlans[profile.uid_ems] = "#{profile.name} (#{profile_network.name})"
      end

      vlans['<Empty>'] = _('<No Profile>')
      vlans['<Template>'] = _('<Use template nics>')
    end

    def local_get_vnic_profiles_in_cluster(uid_ems_cluster)
      cluster_profiles = {}
      profiles = ext_management_system.distributed_virtual_lans
      cluster_networks = all_networks_as_switches_in_cluster(uid_ems_cluster)
      profiles.each do |p|
        profile_network = cluster_networks.detect { |n| n.id == p.switch.id }
        if profile_network
          cluster_profiles[p] = profile_network
        end
      end
      cluster_profiles
    end

    def local_external_vnic_profiles(uid_ems_cluster)
      external_profiles = {}
      cluster = cluster_by_uid_ems(uid_ems_cluster)
      datacenter = cluster.parent_datacenter
      profiles = datacenter.external_distributed_virtual_lans
      external_networks = datacenter.external_distributed_virtual_switches
      profiles.each do |p|
        profile_network = external_networks.detect { |n| n.id == p.switch.id }
        if profile_network
          external_profiles[p] = profile_network
        end
      end
      external_profiles
    end

    def all_networks_as_switches_in_cluster(uid_ems_cluster)
      cluster = cluster_by_uid_ems(uid_ems_cluster)
      cluster&.switches
    end

    def cluster_by_uid_ems(uid_ems)
      ext_management_system.ems_clusters.find_by(:uid_ems => uid_ems)
    end

    def parse_vnic_profile_id(requested_profile, uid_ems_cluster)
      if requested_profile.include?('(')
        vlans = {}
        private_load_allowed_networks_from_provider(vlans, uid_ems_cluster)
        matches = vlans.select { |_profile_id, profile_description| profile_description == requested_profile }
        return matches.keys[0] unless matches.empty?
      end

      requested_profile
    end

    def configure_vnic(args)
      mac_addr = args[:mac_addr]
      vnic = args[:vnic]

      profile_id = args[:vnic_profile]
      nics_service = args[:nics_service]
      options = {
        :name         => args[:nic_name],
        :interface    => args[:interface],
        :mac          => mac_addr ? OvirtSDK4::Mac.new(:address => mac_addr) : nil,
        :vnic_profile => {:id => profile_id}
      }.delete_blanks
      args[:logger].info("with options: <#{options.inspect}>")
      if vnic
        nics_service.nic_service(vnic.id).update(options)
      else
        nics_service.add(OvirtSDK4::Nic.new(options))
      end
    end

    def get_vnic_profiles_in_cluster(uid_ems_cluster)
      cluster_profiles = {}
      ext_management_system.with_provider_connection do |connection|
        profiles = connection.system_service.vnic_profiles_service.list

        cluster_networks = connection.system_service.clusters_service.cluster_service(uid_ems_cluster).networks_service.list

        profiles.each do |p|
          profile_network = cluster_networks.detect { |n| n.id == p.network.id }
          if profile_network
            cluster_profiles[p] = profile_network
          end
        end
      end
      cluster_profiles
    end

    def find_vnic_profile_in_cluster(profile_id, uid_ems_cluster)
      profiles = get_vnic_profiles_in_cluster(uid_ems_cluster)
      profiles.detect { |profile, _profile_network| profile.id == profile_id }
    end
  end
end
