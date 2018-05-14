class ManageIQ::Providers::Redhat::Inventory::Persister::InfraManager < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      infra,
      %i(ems_clusters hosts resource_pools vms miq_templates
         storages vm_and_template_ems_custom_fields disks guest_devices hardwares
         host_hardwares host_networks host_operating_systems host_storages
         host_switches lans networks operating_systems snapshots host_virtual_switches)
    )

    add_inventory_collection(
      infra.datacenters(
        :arel     => manager.ems_folders.where(:type => 'Datacenter'),
        :strategy => :local_db_find_missing_references
      )
    )

    add_inventory_collection(
      infra.ems_folder_children(
        :dependency_attributes => {
          :clusters    => [collections[:ems_clusters]],
          :datacenters => [collections[:datacenters]],
          :vms         => [collections[:vms]],
          :templates   => [collections[:miq_templates]]
        }
      )
    )

    add_inventory_collection(
      infra.ems_clusters_children(
        :dependency_attributes => {
          :vms      => [collections[:vms]],
          :clusters => [collections[:ems_clusters]]
        }
      )
    )

    add_inventory_collection(
      infra.snapshot_parent(
        :dependency_attributes => {
          :snapshots => [collections[:snapshots]]
        }
      )
    )

    add_inventory_collection(
      infra.vm_folders(
        :arel     => manager.ems_folders.where(:name => 'vm'),
        :strategy => :local_db_find_missing_references
      )
    )
    add_inventory_collection(
      infra.host_folders(
        :arel     => manager.ems_folders.where(:name => 'host'),
        :strategy => :local_db_find_missing_references
      )
    )
    add_inventory_collection(
      infra.root_folders(
        :arel     => manager.ems_folders.where(:uid_ems => 'root_dc'),
        :strategy => :local_db_find_missing_references
      )
    )
  end
end
