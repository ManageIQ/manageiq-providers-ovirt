class ManageIQ::Providers::Redhat::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :InfraManager
  require_nested :TargetCollection

  attr_reader :collector

  def initialize(manager, target, collector)
    @manager   = manager
    @target    = target
    @collector = collector

    @collections = {}

    initialize_inventory_collections
  end

  protected

  def infra
    ManageIQ::Providers::Redhat::InventoryCollectionDefault::InfraManager
  end
end
