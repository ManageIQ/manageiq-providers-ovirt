class ManageIQ::Providers::Redhat::Inventory::Persister::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_targeted_inventory_collections
    add_remaining_inventory_collections([infra], :strategy => :local_db_find_references)

    # TODO: check what needs to be added here
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
    add_miq_templates_inventory_collections(references(:miq_templates))
    add_vms_and_miq_templates_inventory_collections(references(:vms) + references(:miq_templates))

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
  end

  # TODO: check correctness
  def add_miq_templates_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.miq_templates(
        :arel     => manager.miq_templates.where(:ems_ref => manager_refs),
        :strategy => :local_db_find_missing_references
      )
    )
  end

  # TODO: check correctness
  def add_vms_and_miq_templates_inventory_collections(manager_refs)
    return if manager_refs.blank?

    add_inventory_collection(
      infra.hardwares(
        :arel     => manager.hardwares.joins(:vm_or_template).where(
          'vms' => {:ems_ref => manager_refs}
        ),
        :strategy => :local_db_find_missing_references
      )
    )
  end
end
