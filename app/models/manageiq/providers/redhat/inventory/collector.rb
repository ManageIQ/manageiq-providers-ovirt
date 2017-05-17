class ManageIQ::Providers::Redhat::Inventory::Collector < ManagerRefresh::Inventory::Collector
  require_nested :InfraManager
  require_nested :TargetCollection

  attr_reader :emsclusters
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
    @emsclusters    = []
    @networks       = []
    @storagedomains = []
    @datacenters    = []
    @hosts          = []
    @vms            = []
    @templates      = []
  end

  def hash_collection
    # TODO: check whether needed
    ::ManageIQ::Providers::Redhat::Inventory::HashCollection
  end

  def collect_emsclusters
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

  def collect_attached_disks(disks_owner)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      attachments = connection.follow_link(disks_owner.disk_attachments)
      attachments.map do |attachment|
        res = connection.follow_link(attachment.disk)
        res.interface = attachment.interface
        res.bootable = attachment.bootable
        res.active = attachment.active
        res
      end
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
