class ManageIQ::Providers::Redhat::Inventory::Persister::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Persister
  include ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraCollections

  def initialize_inventory_collections
    initialize_infra_inventory_collections
  end

  # not added to IC properties
  # IC definitions not written like other providers (used arel property instead)
  def targeted?
    true
  end

  def strategy
    :local_db_find_missing_references
  end
end
