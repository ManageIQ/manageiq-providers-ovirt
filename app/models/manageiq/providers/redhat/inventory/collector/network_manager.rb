class ManageIQ::Providers::Redhat::Inventory::Collector::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Collector::NetworkManager
  def tenants
    @tenants = manager.openstack_handle.tenants
  end
end
