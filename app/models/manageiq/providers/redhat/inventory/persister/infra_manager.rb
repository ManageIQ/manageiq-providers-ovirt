class ManageIQ::Providers::Redhat::Inventory::Persister::InfraManager < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      infra,
      %i(datacenters emsfolders ems_clusters hosts resourcepools vm_or_templates vm
         miq_templates storages custom_attributes customization_specs disks
         guest_devices hardwars lans miq_scsi_luns miq_scsi_targets networks
         operating_systems snapshots switchs system_services)
    )

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
end
