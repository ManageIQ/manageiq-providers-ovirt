class ManageIQ::Providers::Redhat::Inventory::Persister::InfraManager < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_inventory_collections(
      infra,
      %i(datacenters emsfolders emsclusters hosts resourcepools vm_or_templates vm
         miq_templates storages custom_attributes customization_specs disks
         guest_devices hardwars lans miq_scsi_luns miq_scsi_targets networks
         operating_systems snapshots switchs system_services)
    )

    # TODO: check what needs to be added here
  end
end
