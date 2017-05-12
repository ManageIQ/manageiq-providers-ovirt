class ManageIQ::Providers::Redhat::Inventory::Persister::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_targeted_inventory_collections
    add_remaining_inventory_collections([infra], :strategy => :local_db_find_references)

    # add_inventory_collection(
    #   infra.datacenter_children(
    #     :dependency_attributes => {
    #       :folders => [
    #         [collections[:clusters]],
    #         [collections[:vms]]
    #       ]
    #     }
    #   )
    # )

    add_inventory_collection(
      infra.resource_pool_children(
        :dependency_attributes => {
          :vms => [collections[:vms]],
        }
      )
    )

    add_inventory_collection(
      infra.cluster_children(
        :dependency_attributes => {
          :resource_pools => [collections[:resource_pools]],
        }
      )
    )
  end

  def references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :ems_ref).try(:to_a) || []
  end

  # TODO: check whether needed
  def name_references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :name).try(:to_a) || []
  end

  def infra
    ManageIQ::Providers::Redhat::InventoryCollectionDefault::InfraManager
  end

  def add_targeted_inventory_collections
    add_vms_inventory_collections(references(:vms))
    add_resource_pools_inventory_collections(references(:resource_pools))
    add_clusters_inventory_collections(references(:clusters))

    # TODO: check what needs to be added here
  end

  # TODO: check correctness
  def add_vms_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.vms(
        :arel     => manager.vms.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
    add_inventory_collection(
      infra.disks(
        :arel     => manager.disks.joins(:hardware => :vm_or_template).where(
          :hardware => {'vms' => {:ems_ref => manager_refs}}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
    add_inventory_collection(
      infra.nics(
        :arel     => manager.networks.joins(:hardware => :vm_or_template).where(
          :hardware => {'vms' => {:ems_ref => manager_refs}}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_resource_pools_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.resource_pools(
        :arel     => manager.resource_pools.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_clusters_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.clusters(
        :arel     => manager.clusters.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
  end
end
