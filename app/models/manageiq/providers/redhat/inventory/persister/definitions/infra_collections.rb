module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraCollections
  extend ActiveSupport::Concern

  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::ClusterCollections
  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::VmsCollections
  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::HostsCollections
  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::DatacentersCollections
  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::StoragedomainsCollections
  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::NetworksCollections
  include ::ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::VmsDependencyCollections

  def initialize_infra_inventory_collections
    add_collection(infra, :ems_folders)

    add_clusters_group
    add_vms_group
    add_hosts_group
    add_datacenters_group
    add_storagedomains_group
    add_networks_group
    add_vms_dependency_collections_group
    add_other_collections
  end

  # --- IC groups definitions ---

  def add_clusters_group
    add_collection(infra, :ems_clusters)
    add_resource_pools
  end

  def add_vms_group
    add_miq_templates
    add_vm_and_template_ems_custom_fields # TODO we should be able to infer the targeted_arel query

    %i(vms
       disks
       networks
       hardwares
       guest_devices
       snapshots
       operating_systems).each do |name|

      add_collection(infra, name)
    end
  end

  def add_vms_dependency_collections_group
    add_ems_folder_children
    add_ems_cluster_children
    add_snapshot_parent
  end

  def add_datacenters_group
    add_datacenters
  end

  def add_hosts_group
    add_hosts

    %i(host_hardwares
       host_networks
       host_operating_systems
       host_storages
       host_switches).each do |name|

      add_collection(infra, name)
    end
  end

  def add_storagedomains_group
    add_storages
  end

  def add_networks_group
    add_switches
  end

  def add_other_collections
    add_collection(infra, :lans)
  end
end
