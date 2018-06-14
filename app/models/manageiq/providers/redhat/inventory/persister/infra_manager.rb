class ManageIQ::Providers::Redhat::Inventory::Persister::InfraManager < ManageIQ::Providers::Redhat::Inventory::Persister
  include ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraCollections

  def initialize_inventory_collections
    initialize_infra_inventory_collections
  end

  def strategy
    @collection_group == :datacenters ? :local_db_find_missing_references : nil
  end
end
