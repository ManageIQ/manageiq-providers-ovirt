class ManageIQ::Providers::Redhat::Inventory::Persister::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Persister
  include ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraCollections

  def initialize_inventory_collections
    initialize_infra_inventory_collections

    @collection_group = nil
  end

  # not added to IC properties
  # IC definitions not written like other providers (used arel property instead)
  def targeted?
    true
  end

  def strategy
    ems_ref = if @collection_group == :vms_dependency
                references(:vms)
              else
                references(@collection_group)
              end

    if ems_ref.blank?
      :local_db_find_references
    else
      :local_db_find_missing_references unless @collection_group == :vms_dependency
    end
  end
end
