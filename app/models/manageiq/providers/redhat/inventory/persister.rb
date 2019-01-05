class ManageIQ::Providers::Redhat::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :InfraManager
  require_nested :TargetCollection

  def initialize(manager, target)
    @manager   = manager
    @target    = target

    @collections = {}
    @collection_group = nil

    initialize_inventory_collections
  end
end
