class ManageIQ::Providers::Redhat::Inventory::Persister::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_targeted_inventory_collections
    add_remaining_inventory_collections([infra], :strategy => :local_db_find_references)

    add_inventory_collection(
      infra.datacenter_children(
        :dependency_attributes => {
          :folders => [
            [collections[:ems_clusters]],
            [collections[:vms]]
          ]
        }
      )
    )

    add_inventory_collection(
      infra.resource_pool_children(
        :dependency_attributes => {
          :vms => [collections[:vms]],
        }
      )
    )

    add_inventory_collection(
      infra.ems_clusters_children(
        :dependency_attributes => {
          :resource_pools => [collections[:resource_pools]],
        }
      )
    )
  end

  def references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :ems_ref).try(:to_a) || []
  end

  def infra
    ManageIQ::Providers::Redhat::InventoryCollectionDefault::InfraManager
  end

  def add_targeted_inventory_collections
    add_vms_inventory_collections(references(:vms))
    add_resource_pools_inventory_collections(references(:resource_pools))
    add_clusters_inventory_collections(references(:ems_clusters))
    add_datacenters_inventory_collections(references(:datacenters))
    add_storages_inventory_collcetions(references(:storages))
    add_hosts_inventory_collections(references(:hosts))
    add_guest_devices_inventory_collections(references(:guest_devices))
    add_snapshots_inventory_collections(references(:snapshots))
    add_operating_systems_inventory_collections(references(:operating_systems))
    add_custom_attributes_inventory_collections(references(:custom_attributes))
  end

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
    add_inventory_collection(
      infra.hardwares(
        :arel     => manager.hardwares.joins(:vm_or_template).where(
          'vms' => {:ems_ref => manager_refs}
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
      infra.ems_clusters(
        :arel     => manager.ems_clusters.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_datacenters_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.datacenters(
        :arel     => manager.ems_folders.where(:ems_ref => manager_refs, :type => Datacenter),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_storages_inventory_collcetions(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.storages(
        :arel     => manager.storages.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_hosts_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.storages(
        :arel     => manager.hosts.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_guest_devices_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.guest_devices(
        :arel     => GuestDevice.joins(:hardware => :vm_or_template).where(
          :hardware => {'vms' => {:ems_ref => manager_refs}}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_snapshots_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.snapshots(
        :arel     => Snapshot.joins(:vm_or_template).where(
          'vms' => {:ems_ref => manager_refs}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_operating_systems_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.operating_systems(
        :arel     => OperatingSystem.joins(:vm_or_template).where(
          'vms' => {:ems_ref => manager_refs}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  def add_custom_attributes_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.custom_attributes(
        :arel     => manager.ems_custom_attributes.joins(:vm_or_template).where(
          'vms' => {:ems_ref => manager_refs}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end
end
