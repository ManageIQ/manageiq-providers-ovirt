# !! Inherited from OpenStack
class ManageIQ::Providers::Redhat::Inventory::Persister::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Persister::NetworkManager
  include ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::NetworkCollections

  def initialize_inventory_collections
    super
    add_cloud_tenants
    add_guest_devices
  end
end
