module ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies
  require 'ovirt'
  require 'manageiq/providers/ovirt/legacy/inventory'

  class V3
    include Vmdb::Logging

    attr_reader :ext_management_system

    def initialize(args)
      @ext_management_system = args[:ems]
    end

    def get
      self
    end

    # Event parsing

    def username_by_href(href)
      ext_management_system.with_provider_connection do |rhevm|
        Ovirt::User.find_by_href(rhevm, href).try(:[], :user_name)
      end
    end

    def cluster_name_href(href)
      ext_management_system.with_provider_connection do |rhevm|
        Ovirt::Cluster.find_by_href(rhevm, href).try(:[], :name)
      end
    end

    # Provisioning
    def get_host_proxy(host, connection)
      connection ||= ext_management_system.connect
      host_proxy = connection.get_resource_by_ems_ref(host.ems_ref)
      GeneralUpdateMethodNamesDecorator.new(host_proxy)
    end

    def clone_completed?(args)
      source = args[:source]
      phase_context = args[:phase_context]
      logger = args[:logger]
      # TODO: shouldn't this error out the provision???
      return true if phase_context[:clone_task_ref].nil?

      source.with_provider_connection do |rhevm|
        status = rhevm.status(phase_context[:clone_task_ref])
        logger.info("Clone is #{status}")
        status == 'complete'
      end
    end

    def destination_image_locked?(vm)
      vm.with_provider_object do |rhevm_vm|
        return false if rhevm_vm.nil?
        rhevm_vm.attributes.fetch_path(:status, :state) == "image_locked"
      end
    end

    def exists_on_provider?(vm)
      vm.with_provider_object do |_rhevm_vm|
        true
      end
    rescue Ovirt::MissingResourceError
      false
    end

    def populate_phase_context(phase_context, vm)
      phase_context[:new_vm_ems_ref] = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(vm[:href])
      phase_context[:clone_task_ref] = vm.creation_status_link
    end

    def nics_for_vm(vm)
      vm.with_provider_object do |rhevm_vm|
        rhevm_vm.nics.collect { |n| NicsDecorator.new(n) }
      end
    end

    def cluster_find_network_by_name(href, network_name)
      ext_management_system.with_provider_connection do |rhevm|
        Ovirt::Cluster.find_by_href(rhevm, href).try(:find_network_by_name, network_name)
      end
    end

    def configure_vnics(requested_vnics, destination_vnics, dest_cluster, destination_vm)
      requested_vnics.stretch!(destination_vnics).each_with_index do |requested_vnic, idx|
        if requested_vnic.nil?
          # Remove any unneeded vm nics
          destination_vnics[idx].destroy
        else
          configure_vnic_with_requested_data("nic#{idx + 1}", requested_vnic, destination_vnics[idx], dest_cluster, destination_vm)
        end
      end
    end

    def load_allowed_networks(hosts, vlans, workflow)
      workflow.load_hosts_vlans(hosts, vlans)
    end

    def filter_allowed_hosts(workflow, all_hosts)
      workflow.filter_hosts_by_vlan_name(all_hosts)
    end

    def powered_off_in_provider?(vm)
      vm.with_provider_object(&:status)[:state] == "down"
    end

    def powered_on_in_provider?(vm)
      vm.with_provider_object(&:status)[:state] == "up"
    end

    def vm_boot_from_cdrom(operation, name)
      operation.get_provider_destination.boot_from_cdrom(name)
    rescue Ovirt::VmNotReadyToBoot
      raise OvirtServices::VmNotReadyToBoot
    end

    def detach_floppy(operation)
      operation.get_provider_destination.detach_floppy
    end

    def vm_boot_from_network(operation)
      operation.get_provider_destination.boot_from_network
    rescue Ovirt::VmNotReadyToBoot
      raise OvirtServices::VmNotReadyToBoot
    end

    def get_template_proxy(template, connection)
      connection ||= ext_management_system.connect
      template_proxy = connection.get_resource_by_ems_ref(template.ems_ref)
      GeneralUpdateMethodNamesDecorator.new(template_proxy)
    end

    def get_vm_proxy(vm, connection)
      connection ||= ext_management_system.connect
      vm_proxy = connection.get_resource_by_ems_ref(vm.ems_ref)
      GeneralUpdateMethodNamesDecorator.new(vm_proxy)
    end

    def collect_disks_by_hrefs(disks)
      vm_disks = []

      ext_management_system.try(:with_provider_connection) do |rhevm|
        disks.each do |disk|
          begin
            vm_disks << Ovirt::Disk.find_by_href(rhevm, disk)
          rescue Ovirt::MissingResourceError
            nil
          end
        end
      end
      vm_disks
    end

    def shutdown_guest(operation)
      operation.with_provider_object(&:shutdown)
    rescue Ovirt::VmIsNotRunning
    end

    def reboot_guest(operation)
      operation.with_provider_object(&:reboot)
    rescue Ovirt::VmIsNotRunning
    end

    def start_clone(source, clone_options, phase_context)
      source.with_provider_object do |rhevm_template|
        vm = rhevm_template.create_vm(clone_options)
        populate_phase_context(phase_context, vm)
      end
    end

    def vm_start(vm, cloud_init)
      vm.with_provider_object do |rhevm_vm|
        rhevm_vm.start { |action| action.use_cloud_init(true) if cloud_init }
      end
    rescue Ovirt::VmAlreadyRunning
    end

    def vm_stop(vm)
      vm.with_provider_object(&:stop)
    rescue Ovirt::VmIsNotRunning
    end

    def vm_suspend(vm)
      vm.with_provider_object(&:suspend)
    end

    def vm_reconfigure(vm, options = {})
      log_header = "EMS: [#{ext_management_system.name}] #{vm.class.name}: id [#{vm.id}], name [#{vm.name}], ems_ref [#{vm.ems_ref}]"
      spec = options[:spec]

      _log.info("#{log_header} Started...")

      vm.with_provider_object do |rhevm_vm|
        update_vm_memory(rhevm_vm, spec["memoryMB"] * 1.megabyte) if spec["memoryMB"]

        cpu_options = {}
        cpu_options[:cores] = spec["numCoresPerSocket"] if spec["numCoresPerSocket"]
        cpu_options[:sockets] = spec["numCPUs"] / (cpu_options[:cores] || vm.cpu_cores_per_socket) if spec["numCPUs"]

        rhevm_vm.cpu_topology = cpu_options if cpu_options.present?
      end

      _log.info("#{log_header} Completed.")
    end

    def advertised_images
      ext_management_system.with_provider_connection do |rhevm|
        rhevm.iso_images.collect { |image| image[:name] }
      end
    rescue Ovirt::Error => err
      name = ext_management_system.try(:name)
      _log.error("Error Getting ISO Images on ISO Datastore on Management System <#{name}>: #{err.class.name}: #{err}")
      raise ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error, err
    end

    def host_activate(host)
      host.with_provider_object(&:activate)
    end

    def host_deactivate(host)
      host.with_provider_object(&:deactivate)
    end

    def event_fetcher
      EventFetcher.new(ext_management_system)
    end

    class EventFetcher
      def initialize(ems)
        @ext_management_system = ems
        ::Ovirt.logger = $rhevm_log if $rhevm_log
      end

      def inventory
        @inventory ||= ManageIQ::Providers::Ovirt::Legacy::Inventory.new(event_monitor_options)
      end

      delegate :events, :to => :inventory

      def event_monitor_options
        {
          :server     => @ext_management_system.hostname,
          :port       => @ext_management_system.port.blank? ? nil : @ext_management_system.port.to_i,
          :username   => @ext_management_system.authentication_userid,
          :password   => @ext_management_system.authentication_password,
          :verify_ssl => false
        }
      end
    end

    class NicsDecorator < SimpleDelegator
      def name
        self[:name]
      end

      def network
        id = self[:network][:id]
        OpenStruct.new(:id => id)
      end
    end

    class GeneralUpdateMethodNamesDecorator < SimpleDelegator
      def method_missing(method_name, *args, &block)
        str_method_name = method_name.to_s
        if str_method_name =~ /update_.*!/
          attribute_to_update = str_method_name.split("update_")[1].delete('!')
          send("#{attribute_to_update}=", *args, &block)
        else
          # This is requied becasue of Ovirt::Vm strage behaviour - while rhevm.respond_to?(:nics)
          # returns false, rhevm.nics actually works.
          begin
            __getobj__.send(method_name, *args, &block)
          rescue NoMethodError
            super
          end
        end
      end

      def update_memory!(memory, _limit = nil)
        # memory limit is not supported in v3
        self.memory= memory
      end
    end

    def get_mac_address_of_nic_on_requested_vlan(args)
      network = find_network_in_cluster(args[:value_of_vlan_option], args[:dest_cluster])
      return nil if network.nil?

      find_mac_address_on_network(network, args[:destination])
    end

    def find_network_in_cluster(network_name, dest_cluster)
      network = cluster_find_network_by_name(dest_cluster.ems_ref, network_name)

      _log.warn "Cannot find network name=#{network_name}" if network.nil?
      network
    end

    def find_mac_address_on_network(network, destination)
      nics = nics_for_vm(destination)
      nic = nics.detect { |n| n.network.try(:id) == network[:id] }
      _log.warn "Cannot find NIC with network id=#{network[:id].inspect}" if nic.nil?
      nic && nic[:mac] && nic[:mac][:address]
    end

    def collect_external_network_providers
      # Return nothing
    end

    private

    #
    # Hot plug of virtual memory has to be done in quanta of this size. Actually this is configurable in the
    # engine, using the `HotPlugMemoryMultiplicationSizeMb` configuration parameter, but it is very unlikely
    # that it will change.
    #
    HOT_PLUG_DIMM_SIZE = 256.megabyte.freeze

    def update_vm_memory(vm, virtual)
      # Adjust the virtual and guaranteed memory:
      virtual = calculate_adjusted_virtual_memory(vm, virtual)
      guaranteed = calculate_adjusted_guaranteed_memory(vm, virtual)

      # If the virtual machine is running we need to update first the configuration that will be used during the
      # next run, as the guaranteed memory can't be changed for the running virtual machine.
      state = vm.attributes.fetch_path(:status, :state)
      if state == 'up'
        vm.update_memory(virtual, guaranteed, :next_run => true)
        vm.update_memory(virtual, nil)
      else
        vm.update_memory(virtual, guaranteed)
      end
    end

    #
    # Adjusts the new requested virtual memory of a virtual machine so that it satisfies the constraints imposed
    # by the engine.
    #
    # @param vm [Hash] The current representation of the virtual machine.
    #
    # @param requested [Integer] The new amount of virtual memory requested by the user.
    #
    # @return [Integer] The amount of virtual memory requested by the user adjusted so that it satisfies the constrains
    #   imposed by the engine.
    #
    def calculate_adjusted_virtual_memory(vm, requested)
      # Get the current state of the virtual machine, and the current amount of virtual memory:
      attributes = vm.attributes
      name = attributes.fetch_path(:name)
      state = attributes.fetch_path(:status, :state)
      current = attributes.fetch_path(:memory)

      # Initially there is no need for adjustment:
      adjusted = requested

      # If the virtual machine is running then the difference in memory has to be a multiple of 256 MiB, otherwise
      # the engine will not perform the hot plug of the new memory. The reason for this is that hot plugging of
      # memory is performed adding a new virtual DIMM to the virtual machine, and the size of the virtual DIMM
      # is 256 MiB. This means that we need to round the difference up to the closest multiple of 256 MiB.
      if state == 'up'
        delta = requested - current
        remainder = delta % HOT_PLUG_DIMM_SIZE
        if remainder > 0
          adjustment = HOT_PLUG_DIMM_SIZE - remainder
          adjusted = requested + adjustment
          _log.info(
            "The change in virtual memory of virtual machine '#{name}' needs to be a multiple of " \
            "#{HOT_PLUG_DIMM_SIZE / 1.megabyte} MiB, so it will be adjusted to #{adjusted / 1.megabyte} MiB."
          )
        end
      end

      # Return the adjusted memory:
      adjusted
    end

    #
    # Adjusts the guaranteed memory of a virtual machie so that it satisfies the constraints imposed by the
    # engine.
    #
    # @param vm [Hash] The current representation of the virtual machine.
    #
    # @param virtual [Integer] The new amount of virtual memory requested by the user (and maybe already adjusted).
    #
    # @return [Integer] The amount of guarantted memory to request so that it satisfies the constraints imposed by
    #   the engine.
    #
    def calculate_adjusted_guaranteed_memory(vm, virtual)
      # Get the current amount of guaranteed memory:
      attributes = vm.attributes
      name = attributes.fetch_path(:name)
      current = attributes.fetch_path(:memory_policy, :guaranteed)

      # Initially there is no need for adjustment:
      adjusted = current

      # The engine requires that the virtual memory is bigger or equal than the guaranteed memory at any given
      # time. Therefore, we need to adjust the guaranteed memory so that it is the minimum of the previous
      # guaranteed memory and the new virtual memory.
      if current > virtual
        adjusted = virtual
        _log.info(
          "The guaranteed physical memory of virtual machine '#{name}' needs to be less or equal than the virtual " \
          "memory, so it will be adjusted to #{adjusted / 1.megabyte} MiB."
        )
      end

      # Return the adjusted guaranteed memory:
      adjusted
    end

    def configure_vnic(args)
      vnic = args[:vnic]

      options = {
        :name        => args[:nic_name],
        :interface   => args[:interface],
        :network_id  => args[:network][:id],
        :mac_address => args[:mac_addr],
      }.delete_blanks

      args[:logger].info("with options: <#{options.inspect}>")

      if vnic.nil?
        args[:vm].with_provider_object do |rhevm_vm|
          rhevm_vm.create_nic(options)
        end
      else
        vnic.apply_options!(options)
      end
    end

    def configure_vnic_with_requested_data(name, requested_vnic, vnic, dest_cluster, destination_vm)
      network = cluster_find_network_by_name(dest_cluster.ems_ref, requested_vnic[:network])
      raise OvirtServices::NetworkNotFound, "Unable to find specified network: <#{requested_vnic[:network]}>" if network.nil?

      configure_vnic(
        :vm        => destination_vm,
        :mac_addr  => requested_vnic[:mac_address],
        :network   => network,
        :nic_name  => name,
        :interface => requested_vnic[:interface],
        :vnic      => vnic,
        :logger    => _log
      )
    end
  end
end
