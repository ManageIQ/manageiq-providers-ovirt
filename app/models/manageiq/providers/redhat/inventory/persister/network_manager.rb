class ManageIQ::Providers::Redhat::Inventory::Persister::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Persister::NetworkManager
  def network
    ManageIQ::Providers::Redhat::InventoryCollectionDefault::NetworkManager
  end

  def initialize_inventory_collections
    super
    add_inventory_collections(
      network,
      %i(cloud_tenants guest_devices),
      :builder_params => {:ext_management_system => manager.parent_manager}
    )
  end
end
