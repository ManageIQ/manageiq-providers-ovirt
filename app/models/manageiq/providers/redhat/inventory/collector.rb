class ManageIQ::Providers::Redhat::Inventory::Collector < ManagerRefresh::Inventory::Collector
  # TODO: review the changes here and find common parts with ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4
  require_nested :InfraManager
  require_nested :TargetCollection

  attr_reader :ems_clusters
  attr_reader :networks
  attr_reader :storagedomains
  attr_reader :datacenters
  attr_reader :hosts
  attr_reader :vms
  attr_reader :templates

  VERSION_HASH = {:version => 4}.freeze

  def initialize(manager, _target)
    super

    initialize_inventory_sources
  end

  def initialize_inventory_sources
    @ems_clusters   = []
    @networks       = []
    @storagedomains = []
    @datacenters    = []
    @hosts          = []
    @vms            = []
    @templates      = []
  end

  def collect_ems_clusters
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.system_service.clusters_service.list
    end
  end

  def collect_networks
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.system_service.networks_service.list
    end
  end

  def collect_storagedomains
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.system_service.storage_domains_service.list
    end
  end

  def collect_datacenters
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.system_service.data_centers_service.list
    end
  end

  def collect_cluster_for_host(host)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(host.cluster)
    end
  end

  def collect_host_stats(host)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.link?(host.statistics) ? connection.follow_link(host.statistics) : host.statistics
    end
  end

  def collect_datacenter_for_cluster(cluster)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(cluster.data_center)
    end
  end

  def collect_attached_disks(disks_owner)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      AttachedDisksFetcher.collect_attached_disks(disks_owner, connection, preloaded_disks)
    end
  end

  # This code is copied from redhat/infra_manager/inventory/strategies/v4.rb it is a part of other code
  # which will should be extracted to a common place when the graph refresh is stabelized.
  def preloaded_disks
    @preloaded_disks ||= collect_disks_as_hash
  end

  # This code is copied from redhat/infra_manager/inventory/strategies/v4.rb it is a part of other code
  # which will should be extracted to a common place when the graph refresh is stabelized.
  def collect_disks_as_hash
    Hash[connection.system_service.disks_service.list.collect { |d| [d.id, d] }]
  end

  # This code is copied from redhat/infra_manager/inventory/strategies/v4.rb it is a part of other code
  # which will should be extracted to a common place when the graph refresh is stabelized.
  class AttachedDisksFetcher
    def self.collect_attached_disks(disks_owner, connection, preloaded_disks = nil)
      attachments = connection.follow_link(disks_owner.disk_attachments)
      attachments.map do |attachment|
        res = disk_from_attachment(connection, attachment, preloaded_disks)
        res.interface = attachment.interface
        res.bootable = attachment.bootable
        res.active = attachment.active
        res
      end
    end

    def self.disk_from_attachment(connection, attachment, preloaded_disks)
      disk = preloaded_disks && preloaded_disks[attachment.disk.id]
      disk || connection.follow_link(attachment.disk)
    end
  end

  def collect_nics(nic_owner)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(nic_owner.nics)
    end
  end

  def collect_vm_devices(vm)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(vm.reported_devices)
    end
  end

  def collect_snapshots(vm)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(vm.snapshots)
    end
  end

  def collect_host_nics(host)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(host.nics)
    end
  end

  def collect_dc_domains(dc)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      connection.follow_link(dc.storage_domains)
    end
  end
end
