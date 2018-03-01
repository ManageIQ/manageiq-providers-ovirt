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
  include_concern :AdminUI

  has_many :cloud_tenants, :foreign_key => :ems_id, :dependent => :destroy
  has_many :vm_and_template_ems_custom_fields, :through => :vms_and_templates, :source => :ems_custom_attributes

  include HasNetworkManagerMixin

  supports :provisioning
  supports :refresh_new_target
  supports :vm_import do
    # The version of the RHV needs to be at least 4.1.5 due to https://bugzilla.redhat.com/1477375
    unsupported_reason_add(:vm_import, _('Cannot import to a RHV provider of version < 4.1.5')) unless version_at_least?('4.1.5')
  end

  def supports_admin_ui?
    # Link to oVirt Admin UI is supported for Engine version 4.1.8 or better.
    # See https://bugzilla.redhat.com/1512989 for details.
    version_at_least?('4.1.8')
  end

  def ensure_managers
    return unless enabled
    ensure_network_manager
    if network_manager
      network_manager.name = "#{name} Network Manager"
      network_manager.zone_id = zone_id
      network_manager.provider_region = provider_region
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

        unless ems_was_removed
          build_network_manager(:type => 'ManageIQ::Providers::Redhat::NetworkManager')
        end
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

  def supported_catalog_types
    %w(redhat)
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

  def vm_migrate(vm, options = {}, timeout = 30, limit = 100)
    host_id = URI(options[:host]).path.split('/').last

    migration_options = {
      :host => {
        :id => host_id
      }
    }

    started_time = Time.zone.now
    with_version4_vm_service(vm) do |service|
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
        raise ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error
      end
    end

    raise ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error if finished_event.event_type == "VM_MIGRATION_FAILED_FROM_TO"
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
end
