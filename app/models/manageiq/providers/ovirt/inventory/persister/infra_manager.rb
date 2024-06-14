class ManageIQ::Providers::Ovirt::Inventory::Persister::InfraManager < ManageIQ::Providers::Ovirt::Inventory::Persister
  def initialize_inventory_collections
    add_collection(infra, :disks)
    add_collection(infra, :clusters, :secondary_refs => {:by_uid_ems => %i[uid_ems]})
    add_collection(infra, :ems_folders)
    add_collection(infra, :guest_devices)
    add_collection(infra, :hardwares)
    add_collection(infra, :vm_and_template_ems_custom_fields)
    add_collection(infra, :hosts) do |builder|
      builder.add_default_values(:vmm_vendor => manager.class.host_vendor)
    end
    add_collection(infra, :host_guest_devices)
    add_collection(infra, :host_hardwares)
    add_collection(infra, :host_networks)
    add_collection(infra, :host_operating_systems)
    add_collection(infra, :host_storages)
    add_collection(infra, :host_switches)
    add_collection(infra, :host_virtual_switches)
    add_collection(infra, :distributed_virtual_lans) do |builder|
      builder.add_properties(:model_class => Lan)
      builder.add_properties(:complete => !targeted?)
    end
    add_collection(infra, :networks)
    add_collection(infra, :operating_systems)
    add_collection(infra, :vms) do |builder|
      builder.add_default_values(:vendor => manager.class.vm_vendor)
    end
    add_collection(infra, :iso_images)

    add_miq_templates
    add_resource_pools
    add_snapshots
    add_storages

    add_collection(infra, :distributed_virtual_switches)
    add_collection(infra, :external_distributed_virtual_switches) do |builder|
      builder.add_properties(
        :manager_ref          => %i[uid_ems],
        :attributes_blacklist => %i[parent],
        :secondary_refs       => {:by_switch_uuid => %i[switch_uuid]}
      )
      builder.add_default_values(:ems_id => ->(persister) { persister.manager.id })
    end
    add_collection(infra, :external_distributed_virtual_lans) do |builder|
      builder.add_properties(
        :manager_ref                  => %i[switch uid_ems],
        :parent_inventory_collections => %i[external_distributed_virtual_switches],
        :model_class                  => Lan,
        :complete                     => !targeted?
      )
    end

    add_parent_blue_folders

    add_collection(infra, :root_folder_relationship)
    add_collection(infra, :vm_resource_pools)
    add_collection(infra, :vm_parent_blue_folders)
  end

  # group :clusters
  def add_resource_pools
    add_collection(infra, :resource_pools) do |builder|
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.resource_pools.where(:uid_ems => references(:clusters).collect { |ref| "#{URI(ref).path.split('/').last}_respool" })
          end
        )
      end
    end
  end

  def add_storages
    iso_datastores_reconnect_block = lambda do |inventory_collection, inventory_objects_index, attributes_index|
      # You can only have a single ISO datastore per Ovirt datacenter
      iso_datastore = inventory_collection.parent.iso_datastores.first
      return if iso_datastore.nil?

      _, data = inventory_objects_index.detect { |_ref, data| data[:store_type] == "ISO" }
      data.id = iso_datastore.id
    end

    add_collection(infra, :storages) do |builder|
      builder.add_properties(:custom_reconnect_block => iso_datastores_reconnect_block)
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            ::Storage.where(:ems_ref => references(:storagedomains))
          end
        )
      end
    end
  end

  def add_miq_templates
    add_collection(infra, :miq_templates) do |builder|
      builder.add_default_values(:vendor => manager.class.vm_vendor)
      builder.add_properties(:manager_uuids => references(:vms)) if targeted?
    end
  end

  def add_snapshots
    add_collection(infra, :snapshots) do |builder|
      builder.add_properties(
        :manager_ref => %i(uid),
        :strategy    => :local_db_find_missing_references,
      )
    end
  end

  def add_parent_blue_folders
    add_collection(infra, :parent_blue_folders) do |builder|
      dependency_collections = %i[clusters ems_folders hosts resource_pools storages distributed_virtual_switches external_distributed_virtual_switches]
      dependency_attributes = dependency_collections.each_with_object({}) do |collection, hash|
        hash[collection] = ->(persister) { [persister.collections[collection]].compact }
      end
      builder.add_dependency_attributes(dependency_attributes)
    end
  end
end
