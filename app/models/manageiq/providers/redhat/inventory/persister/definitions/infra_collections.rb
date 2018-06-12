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
    @collection_group = nil

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
    @collection_group = :ems_clusters

    add_ems_clusters
    add_resource_pools
  end

  def add_vms_group
    @collection_group = :vms

    add_vms
    add_miq_templates
    add_disks
    add_networks
    add_hardwares
    add_guest_devices
    add_snapshots
    add_operating_systems
    add_vm_and_template_ems_custom_fields
  end

  def add_vms_dependency_collections_group
    @collection_group = :vms_dependency

    add_ems_folder_children
    add_ems_cluster_children
    add_snapshot_parent
  end

  def add_datacenters_group
    @collection_group = :datacenters

    add_datacenters
  end

  def add_hosts_group
    @collection_group = :hosts

    add_hosts
    add_host_hardwares
    add_host_networks
    add_host_operating_systems
    add_host_storages
    add_host_switches
  end

  def add_storagedomains_group
    @collection_group = :storagedomains

    add_storages
  end

  def add_networks_group
    @collection_group = :networks

    add_switches
  end

  def add_other_collections
    @collection_group = nil

    add_collection(infra, :lans)
  end
end
