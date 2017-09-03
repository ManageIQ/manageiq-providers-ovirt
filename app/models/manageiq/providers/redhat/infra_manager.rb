class ManageIQ::Providers::Redhat::InfraManager < ManageIQ::Providers::InfraManager
  require_nested  :EventCatcher
  require_nested  :EventParser
  require_nested  :RefreshWorker
  require_nested  :MetricsCapture
  require_nested  :MetricsCollectorWorker
  require_nested  :Host
  require_nested  :Provision
  require_nested  :ProvisionViaIso
  require_nested  :ProvisionViaPxe
  require_nested  :ProvisionWorkflow
  require_nested  :Refresh
  require_nested  :Template
  require_nested  :Vm
  include_concern :ApiIntegration
  include_concern :VmImport

  has_many :cloud_tenants, :foreign_key => :ems_id, :dependent => :destroy

  include HasNetworkManagerMixin

  supports :provisioning
  supports :refresh_new_target

  before_update :ensure_managers
  before_update :ensure_managers_zone_and_provider_region

  def ensure_network_manager
    auth_url = ovirt_services.collect_external_network_providers.first.authentication_url # TODO - Alona - How to find the ovn via the providers? Is there only one?
    if (auth_url)
      build_network_manager(:type => 'ManageIQ::Providers::Redhat::NetworkManager') unless network_manager
      uri = URI.parse(auth_url)
      parse_network_manager_url(uri)
    end
    # TODO - Alona - if there is no ovn but previoulsy was, should remove from db?
  end

  def parse_network_manager_url(uri)
    network_manager.hostname = uri.host
    network_manager.port = uri.port

    network_manager.api_version = uri.path.split('/').last.split('.').first

    if (uri.instance_of? URI::HTTPS)
      network_manager.security_protocol = "ssl"
    else
      if (uri.instance_of? URI::HTTP)
        network_manager.security_protocol = "non-ssl"
      end
    end
  end

  def refresher
    Refresh::RefresherBuilder.new(self).build
  end

  def self.ems_type
    @ems_type ||= "rhevm".freeze
  end

  def self.description
    @description ||= "Red Hat Virtualization".freeze
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

  def host_quick_stats(host)
    qs = {}
    with_provider_connection(:version => 4) do |connection|
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

  def vm_reconfigure(vm, options = {})
    ovirt_services_for_reconfigure = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Builder.new(self)
      .build(:use_highest_supported_version => true).new(:ems => self)
    ovirt_services_for_reconfigure.vm_reconfigure(vm, options)
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

  def vm_migrate(vm, options = {})
    host_id = URI(options[:host]).path.split('/').last

    migration_options = {
      :host => {
        :id => host_id
      }
    }

    with_version4_vm_service(vm) do |service|
      service.migrate(migration_options)
    end
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

  def version_higher_than?(version)
    return false if api_version.nil?

    ems_version = api_version[/\d+\.\d+\.?\d*/x]
    Gem::Version.new(ems_version) >= Gem::Version.new(version)
  end
end
