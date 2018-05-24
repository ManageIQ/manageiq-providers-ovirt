class ManageIQ::Providers::Redhat::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :InfraManager
  require_nested :TargetCollection

  attr_reader :collector

  def initialize(manager, target, collector)
    @manager   = manager
    @target    = target
    @collector = collector

    @collections = {}
    @collection_group = nil

    initialize_inventory_collections
  end

  protected

  # should be overriden by subclasses
  def strategy
    nil
  end

  def parent
    manager.presence
  end

  # Shared properties for InventoryCollections
  def shared_options
    {
      :parent   => parent,
      :strategy => strategy
    }
  end

  def manager_refs
    references(@collection_group)
  end
end
