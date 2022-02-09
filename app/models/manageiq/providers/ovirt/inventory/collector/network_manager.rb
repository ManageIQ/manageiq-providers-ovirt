class ManageIQ::Providers::Ovirt::Inventory::Collector::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Collector::NetworkManager
  def security_groups
    supports_security_groups? ? super : []
  end

  def tenants
    @tenants = manager.openstack_handle.tenants
  end

  private

  def supports_security_groups?
    rhv_api_version >= Gem::Version.new("4.3") || rhv_api_version < Gem::Version.new("4.2.7")
  end

  def rhv_api_version
    infra_manager = manager.parent_manager
    Gem::Version.new(infra_manager.api_version) if infra_manager.api_version
  end
end
