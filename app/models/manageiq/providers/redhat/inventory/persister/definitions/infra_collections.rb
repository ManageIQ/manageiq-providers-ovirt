module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraCollections
  extend ActiveSupport::Concern

  def initialize_infra_inventory_collections
    %i[disks
       ems_folders
       guest_devices
       hardwares
       vm_and_template_ems_custom_fields
       hosts
       host_guest_devices
       host_hardwares
       host_networks
       host_operating_systems
       host_storages
       host_switches
       host_virtual_switches
       lans
       networks
       operating_systems
       vms].each do |name|

      add_collection(infra, name)
    end

    add_ems_clusters
    add_datacenters
    add_miq_templates
    add_resource_pools
    add_snapshots
    add_storages

    %i[parent_blue_folders
       root_folder_relationship
       vm_resource_pools
       vm_parent_blue_folders].each do |name|

      add_collection(infra, name)
    end
  end

  # ------ IC provider specific definitions -------------------------

  def add_ems_clusters
    add_collection(infra, :ems_clusters, :secondary_refs => {:by_uid_ems => %i[uid_ems]})
  end

  # group :ems_clusters
  def add_resource_pools
    add_collection(infra, :resource_pools) do |builder|
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.resource_pools.where(:uid_ems => references(:ems_clusters).collect { |ref| "#{URI(ref).path.split('/').last}_respool" })
          end
        )
      end
    end
  end

  def add_datacenters
    add_collection(infra, :datacenters) do |builder|
      builder.add_properties(:arel => manager.ems_folders.where(:type => 'Datacenter'))

      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.ems_folders.where(:type => 'Datacenter').where(:ems_ref => references(:datacenters))
          end
        )
      end
    end
  end

  def add_storages
    add_collection(infra, :storages) do |builder|
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
      builder.add_properties(:model_class => ::ManageIQ::Providers::Redhat::InfraManager::Template)

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
end
