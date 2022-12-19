class ManageIQ::Providers::Ovirt::InfraManager < ManageIQ::Providers::InfraManager
  require_nested  :Cluster
  require_nested  :Datacenter
  require_nested  :EventCatcher
  require_nested  :EventParser
  require_nested  :EventTargetParser
  require_nested  :Folder
  require_nested  :RefreshWorker
  require_nested  :Refresher
  require_nested  :ResourcePool
  require_nested  :MetricsCapture
  require_nested  :MetricsCollectorWorker
  require_nested  :Host
  require_nested  :Provision
  require_nested  :ProvisionViaIso
  require_nested  :ProvisionViaPxe
  require_nested  :ProvisionWorkflow
  require_nested  :Snapshot
  require_nested  :Storage
  require_nested  :IsoDatastore
  require_nested  :Template
  require_nested  :Vm
  require_nested  :DistributedVirtualSwitch
  include_concern :ApiIntegration
  include_concern :AdminUI

  has_many :cloud_tenants, :foreign_key => :ems_id, :dependent => :destroy
  has_many :vm_and_template_ems_custom_fields, :through => :vms_and_templates, :source => :ems_custom_attributes
  has_many :external_distributed_virtual_switches, :dependent => :destroy, :foreign_key => :ems_id, :inverse_of => :ext_management_system
  has_many :external_distributed_virtual_lans, -> { distinct }, :through => :external_distributed_virtual_switches, :source => :lans
  has_many :iso_datastores, :dependent => :destroy, :foreign_key => :ems_id, :inverse_of => :ext_management_system
  has_many :iso_images, :through => :storages

  include HasNetworkManagerMixin

  has_one :network_manager,
          :foreign_key => :parent_ems_id,
          :class_name  => "ManageIQ::Providers::Ovirt::NetworkManager",
          :autosave    => true,
          :inverse_of  => :parent_manager,
          :dependent   => :destroy

  supports :catalog
  supports :create
  supports :metrics
  supports :provisioning

  supports :admin_ui do
    # Link to oVirt Admin UI is supported for Engine version 4.1.8 or better.
    # See https://bugzilla.redhat.com/1512989 for details.
    unsupported_reason_add(:admin_ui, _('Admin UI is supported on version >= 4.1.8')) unless version_at_least?('4.1.8')
  end

  supports :create_iso_datastore do
    unsupported_reason_add(:create_iso_datastore, _("Already has an ISO datastore")) unless iso_datastores.empty?
  end

  def ensure_managers
    return unless enabled
    ensure_network_manager
    if network_manager
      network_manager.name = "#{name} Network Manager"
      network_manager.zone_id = zone_id
      network_manager.provider_region = provider_region
      network_manager.tenant_id = tenant_id
      network_manager.save!
    end
  end

  def ensure_network_manager
    providers = ovirt_services.collect_external_network_providers

    unless providers.blank?
      providers = providers.sort_by(&:name)
      auth_url = providers.first.authentication_url
    end

    if auth_url
      if network_manager.nil?
        ems_was_removed = false

        if id # before update
          ems = ExtManagementSystem.find_by(:id => id)
          ems_was_removed = ems.nil? || !ems.enabled
        end

        build_network_manager unless ems_was_removed
      end

      if network_manager
        populate_network_manager_connectivity(auth_url)
      end
    elsif network_manager
      network_manager.destroy_queue
    end
  end

  def populate_network_manager_connectivity(auth_url)
    uri = URI.parse(auth_url)
    network_manager.hostname = uri.host
    network_manager.port = uri.port

    network_manager.api_version = uri.path.split('/').last.split('.').first

    if uri.instance_of?(URI::HTTPS)
      network_manager.security_protocol = "ssl"
    elsif uri.instance_of?(URI::HTTP)
      network_manager.security_protocol = "non-ssl"
    end
  end

  def self.ems_type
    @ems_type ||= "ovirt".freeze
  end

  def self.description
    @description ||= "oVirt".freeze
  end

  def self.vm_vendor
    "ovirt".freeze
  end

  def self.host_vendor
    "ovirt".freeze
  end

  def self.default_blacklisted_event_names
    %w(
      UNASSIGNED
      USER_REMOVE_VG
      USER_REMOVE_VG_FAILED
      USER_VDC_LOGIN
      USER_VDC_LOGOUT
      USER_VDC_LOGIN_FAILED
    )
  end

  def self.without_iso_datastores
    includes(:iso_datastore).where(:iso_datastores => {:id => nil})
  end

  def self.any_without_iso_datastores?
    without_iso_datastores.count > 0
  end

  def self.event_monitor_class
    self::EventCatcher
  end

  def self.ems_settings
    ::Settings.ems.ems_ovirt
  end

  def self.ems_refresh_settings
    ::Settings.ems_refresh.ovirt
  end

  def self.params_for_create
    {
      :fields => [
        {
          :component => 'sub-form',
          :id        => 'endpoints-subform',
          :name      => 'endpoints-subform',
          :title     => _("Endpoints"),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :id        => 'default-tab',
                :name      => 'default-tab',
                :title     => _('Default'),
                :fields    => [
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => 'endpoints.default.valid',
                    :name                   => 'endpoints.default.valid',
                    :skipSubmit             => true,
                    :validationDependencies => %w[type zone_id],
                    :isRequired             => true,
                    :fields                 => [
                      {
                        :component  => "text-field",
                        :id         => "endpoints.default.hostname",
                        :name       => "endpoints.default.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}]
                      },
                      {
                        :component    => "select",
                        :id           => "endpoints.default.verify_ssl",
                        :name         => "endpoints.default.verify_ssl",
                        :label        => _("SSL verification"),
                        :dataType     => "integer",
                        :isRequired   => true,
                        :initialValue => OpenSSL::SSL::VERIFY_PEER,
                        :options      => [
                          {
                            :label => _('Do not verify'),
                            :value => OpenSSL::SSL::VERIFY_NONE,
                          },
                          {
                            :label => _('Verify'),
                            :value => OpenSSL::SSL::VERIFY_PEER,
                          },
                        ]
                      },
                      {
                        :component  => "textarea",
                        :name       => "endpoints.default.certificate_authority",
                        :id         => "endpoints.default.certificate_authority",
                        :label      => _("Trusted CA Certificates"),
                        :rows       => 10,
                        :isRequired => true,
                        :helperText => _('Paste here the trusted CA certificates, in PEM format.'),
                        :validate   => [{:type => "required"}],
                        :condition  => {
                          :when => 'endpoints.default.verify_ssl',
                          :is   => OpenSSL::SSL::VERIFY_PEER,
                        },
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.default.port",
                        :name         => "endpoints.default.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                        :initialValue => 443,
                      },
                      {
                        :component  => "text-field",
                        :id         => "authentications.default.userid",
                        :name       => "authentications.default.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}]
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.default.password",
                        :name       => "authentications.default.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}]
                      },
                    ],
                  },
                ],
              },
              {
                :component => 'tab-item',
                :id        => 'metrics-tab',
                :name      => 'metrics-tab',
                :title     => _('Metrics'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :id           => 'metricsEnable',
                    :name         => 'metricsEnable',
                    :skipSubmit   => true,
                    :initialValue => 'disabled',
                    :label        => _('Enabled'),
                    :options      => [
                      {
                        :label => _('Disabled'),
                        :value => 'disabled'
                      },
                      {
                        :label => _('Enabled'),
                        :value => 'enabled',
                        :pivot => 'endpoints.metrics.hostname'
                      },
                    ],
                  },
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => 'endpoints.metrics.valid',
                    :name                   => 'endpoints.metrics.valid',
                    :skipSubmit             => true,
                    :validationDependencies => %w[type zone_id],
                    :condition  => {
                      :when => 'metricsEnable',
                      :is   => 'enabled',
                    },
                    :fields                 => [
                      {
                        :component  => "text-field",
                        :id         => "endpoints.metrics.hostname",
                        :name       => "endpoints.metrics.hostname",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.metrics.port",
                        :name         => "endpoints.metrics.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :initialValue => 5432,
                      },
                      {
                        :component => "text-field",
                        :id        => "authentications.metrics.userid",
                        :name      => "authentications.metrics.userid",
                        :label     => _("Username"),
                      },
                      {
                        :component => "password-field",
                        :id        => "authentications.metrics.password",
                        :name      => "authentications.metrics.password",
                        :label     => _("Password"),
                        :type      => "password",
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.metrics.path",
                        :name         => "endpoints.metrics.path",
                        :label        => _("Database name"),
                        :initialValue => 'ovirt_engine_history',
                      },
                    ],
                  }
                ],
              },
              {
                :component => 'tab-item',
                :id        => 'keypair-tab',
                :name      => 'keypair-tab',
                :title     => _('RSA key pair'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :id           => 'keypairEnable',
                    :name         => 'keypairEnable',
                    :skipSubmit   => true,
                    :initialValue => 'disabled',
                    :label        => _('Enabled'),
                    :options      => [
                      {
                        :label => _('Disabled'),
                        :value => 'disabled'
                      },
                      {
                        :label => _('Enabled'),
                        :value => 'enabled',
                        :pivot => 'authentications.ssh_keypair.userid'
                      },
                    ],
                  },
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => 'endpoints.ssh_keypair.valid',
                    :name                   => 'endpoints.ssh_keypair.valid',
                    :skipSubmit             => true,
                    :validationDependencies => %w[type zone_id],
                    :condition  => {
                      :when => 'keypairEnable',
                      :is   => 'enabled',
                    },
                    :fields                 => [
                      {
                        :component  => "text-field",
                        :id         => "authentications.ssh_keypair.userid",
                        :name       => "authentications.ssh_keypair.userid",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :label      => _("Username"),
                      },
                      {
                        :component      => "password-field",
                        :id             => "authentications.ssh_keypair.auth_key",
                        :name           => "authentications.ssh_keypair.auth_key",
                        :componentClass => 'textarea',
                        :rows           => 10,
                        :label          => _("Private Key"),
                      },
                    ],
                  }
                ],
              },
            ]
          ]
        },
      ]
    }.freeze
  end

  def host_quick_stats(host)
    qs = {}
    with_provider_connection do |connection|
      stats_list = connection.system_service.hosts_service.host_service(host.uid_ems)
                             .statistics_service.list
      qs["overallMemoryUsage"] = stats_list.detect { |x| x.name == "memory.used" }
                                           .values.first.datum
      qs["overallCpuUsage"] = stats_list.detect { |x| x.name == "cpu.load.avg.5m" }
                                        .values.first.datum
    end
    qs
  end

  def self.provision_class(via)
    case via
    when "iso" then self::ProvisionViaIso
    when "pxe" then self::ProvisionViaPxe
    else            self::Provision
    end
  end

  def self.catalog_types
    {"ovirt" => N_("oVirt")}
  end

  def vm_reconfigure(vm, options = {})
    ovirt_services.vm_reconfigure(vm, options)
  end

  def vm_set_memory(vm, options = {})
    spec = { 'memoryMB' => options[:value] }
    vm_reconfigure(vm, :spec => spec)
  end

  def vm_set_num_cpus(vm, options = {})
    cpu_total = options[:value]
    spec = { 'numCPUs' => cpu_total }
    cpu_sockets = cpu_total / vm.cpu_cores_per_socket
    spec['numCoresPerSocket'] = cpu_total if cpu_sockets < 1
    vm_reconfigure(vm, :spec => spec)
  end

  def add_disks(add_disks_spec, vm)
    storage = add_disks_spec[:storage]
    with_disk_attachments_service(vm) do |service|
      add_disks_spec[:disks].each { |disk_spec| service.add(prepare_disk(disk_spec, storage)) }
    end
  end

  # prepare disk attachment request payload of adding disk for reconfigure vm
  def prepare_disk(disk_spec, storage)
    disk_spec = disk_spec.symbolize_keys
    da_options = {
      :size_in_mb       => disk_spec[:disk_size_in_mb],
      :storage          => storage,
      :name             => disk_spec[:disk_name],
      :thin_provisioned => disk_spec[:thin_provisioned],
      :bootable         => disk_spec[:bootable],
    }

    disk_attachment_builder = DiskAttachmentBuilder.new(da_options)
    disk_attachment_builder.disk_attachment
  end

  # add disk to a virtual machine for a request arrived from an automation call
  def vm_add_disk(vm, options = {})
    storage = options[:datastore] || vm.storage
    raise _("Datastore does not exist, unable to add disk") unless storage

    da_options = {
      :size_in_mb       => options[:diskSize],
      :storage          => storage,
      :name             => options[:diskName],
      :thin_provisioned => options[:thinProvisioned],
      :bootable         => options[:bootable],
      :interface        => options[:interface]
    }

    disk_attachment_builder = DiskAttachmentBuilder.new(da_options)
    with_disk_attachments_service(vm) do |service|
      service.add(disk_attachment_builder.disk_attachment)
    end
  end

  def vm_migrate(vm, options = {}, timeout = 30, limit = 100)
    host_id = URI(options[:host]).path.split('/').last

    migration_options = {
      :host => {
        :id => host_id
      }
    }

    started_time = Time.zone.now
    with_vm_service(vm) do |service|
      service.migrate(migration_options)
    end

    finished_event = nil
    times = 0
    while finished_event.nil?
      times += 1
      sleep timeout
      finished_event = vm.ems_events.where(:event_type => %w[VM_MIGRATION_FAILED_FROM_TO VM_MIGRATION_DONE])
                         .find_by(EventStream.arel_table[:timestamp].gt(started_time))
      if times == limit
        _log.error("Migration event no received failing the request")
        raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error
      end
    end

    raise ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error if finished_event.event_type == "VM_MIGRATION_FAILED_FROM_TO"
  end

  def unsupported_migration_options
    [:storage, :respool, :folder, :datacenter, :host_filter, :cluster]
  end

  # Migrations are supposed to work only in one cluster. If more VMs are going
  # to be migrated, all have to live on the same cluster, otherwise they can
  # not be migrated together.
  def supports_migrate_for_all?(vms)
    vms.map(&:ems_cluster).uniq.compact.size == 1
  end

  def version_at_least?(version)
    return false if api_version.nil?

    ems_version = api_version[/\d+\.\d+\.?\d*/x]
    Gem::Version.new(ems_version) >= Gem::Version.new(version)
  end

  def self.display_name(number = 1)
    n_('Infrastructure Provider (oVirt)', 'Infrastructure Providers (oVirt)', number)
  end
end
