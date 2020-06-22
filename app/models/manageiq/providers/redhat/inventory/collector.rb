class ManageIQ::Providers::Redhat::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  # TODO: review the changes here and find common parts with ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4
  require_nested :InfraManager
  require_nested :TargetCollection

  attr_reader :clusters
  attr_reader :networks
  attr_reader :storagedomains
  attr_reader :datacenters
  attr_reader :hosts
  attr_reader :vms
  attr_reader :templates
  attr_reader :guest_applications

  def initialize(manager, _target)
    super

    initialize_inventory_sources
  end

  def initialize_inventory_sources
    @clusters           = []
    @networks           = []
    @storagedomains     = []
    @datacenters        = []
    @hosts              = []
    @vms                = []
    @templates          = []
    @guest_applications = []
  end

  def collect_clusters
    manager.with_provider_connection do |connection|
      connection.system_service.clusters_service.list
    end
  end

  def collect_networks
    manager.with_provider_connection do |connection|
      connection.system_service.networks_service.list
    end
  end

  def collect_network_attachments(host_id)
    manager.with_provider_connection do |connection|
      connection.system_service.hosts_service.host_service(host_id).network_attachments_service.list
    end
  end

  def collect_vnic_profiles
    @vnic_profiles ||= manager.with_provider_connection do |connection|
      connection.system_service.vnic_profiles_service.list
    end
  end

  def collect_storagedomains
    manager.with_provider_connection do |connection|
      connection.system_service.storage_domains_service.list
    end
  end

  def collect_datacenters
    manager.with_provider_connection do |connection|
      connection.system_service.data_centers_service.list
    end
  end

  def collect_cluster_for_host(host)
    manager.with_provider_connection do |connection|
      connection.follow_link(host.cluster)
    end
  end

  def collect_host_stats(host)
    manager.with_provider_connection do |connection|
      connection.link?(host.statistics) ? connection.follow_link(host.statistics) : host.statistics
    end
  end

  def collect_datacenter_for_cluster(cluster)
    return unless cluster.data_center

    manager.with_provider_connection do |connection|
      connection.follow_link(cluster.data_center)
    end
  end

  def collect_attached_disks(disks_owner)
    manager.with_provider_connection do |connection|
      ManageIQ::Providers::Redhat::InfraManager::Inventory::DisksHelper.collect_attached_disks(disks_owner, connection, preloaded_disks)
    end
  end

  def preloaded_disks
    @preloaded_disks ||= collect_disks_as_hash
  end

  def collect_disks_as_hash
    manager.with_provider_connection do |connection|
      ManageIQ::Providers::Redhat::InfraManager::Inventory::DisksHelper.collect_disks_as_hash(connection)
    end
  end

  def collect_nics(nic_owner)
    manager.with_provider_connection do |connection|
      connection.follow_link(nic_owner.nics)
    end
  end

  def collect_vm_devices(vm)
    manager.with_provider_connection do |connection|
      connection.follow_link(vm.reported_devices)
    end
  end

  def collect_snapshots(vm)
    manager.with_provider_connection do |connection|
      snapshots = connection.follow_link(vm.snapshots)
      self.class.add_snapshot_disks_total_size(connection, snapshots, vm.id)
    end
  end

  def self.add_snapshot_disks_total_size(connection, snapshots, vm_id)
    snapshots.each do |snapshot|
      snapshot.extend(ManageIQ::Providers::Redhat::InfraManager::SnapshotDisksMixin)
      total_size = snapshot.disks_total_size(connection, vm_id)
      snapshot.instance_variable_set(:@total_size, total_size)
    end
  end

  def collect_host_nics(host)
    manager.with_provider_connection do |connection|
      connection.follow_link(host.nics)
    end
  end

  def collect_dc_domains(dc)
    return unless dc

    manager.with_provider_connection do |connection|
      connection.follow_link(dc.storage_domains)
    end
  end

  def collect_disks_of_snapshot(snapshot)
    manager.with_provider_connection do |connection|
      connection.follow_link(snapshot.disks)
    end
  end

  def collect_vm_disks(vm)
    manager.with_provider_connection do |connection|
      disk_attachments = connection.follow_link(vm.disk_attachments)
      disk_attachments.collect do |disk_attachment|
        connection.follow_link(disk_attachment.disk)
      end
    end
  end

  def collect_vm_guest_applications(vm)
    manager.with_provider_connection do |connection|
      connection.follow_link(vm.applications)
    end
  end

  def vm_or_template_by_path(path)
    uuid = ::File.basename(path, '.*')
    vm = vm_by_uuid(uuid)
    vm = template_by_uuid(uuid) if vm.blank?
    vm
  end

  def vm_by_uuid(uuid)
    manager.with_provider_connection do |connection|
      connection.system_service.vms_service.vm_service(uuid).get
    rescue OvirtSDK4::Error # when 404
      nil
    end
  end

  def template_by_uuid(uuid)
    manager.with_provider_connection do |connection|
      connection.system_service.templates_service.template_service(uuid).get
    rescue OvirtSDK4::Error # when 404
      nil
    end
  end
end
