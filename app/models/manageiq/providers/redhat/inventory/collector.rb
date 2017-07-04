class ManageIQ::Providers::Redhat::Inventory::Collector < ManagerRefresh::Inventory::Collector
  require_nested :InfraManager
  require_nested :TargetCollection

  attr_reader :clusters
  attr_reader :vmpools
  attr_reader :networks
  attr_reader :storagedomains
  attr_reader :datacenters
  attr_reader :hosts
  attr_reader :vms
  attr_reader :templates

  def initialize(_manager, _target)
    super

    initialize_inventory_sources
  end

  def initialize_inventory_sources
    @clusters       = []
    @vmpools        = []
    @networks       = []
    @storagedomains = []
    @datacenters    = []
    @hosts          = []
    @vms            = []
    @templates      = []
  end

  def hash_collection
    ::ManageIQ::Providers::Redhat::Inventory::HashCollection
  end
end
