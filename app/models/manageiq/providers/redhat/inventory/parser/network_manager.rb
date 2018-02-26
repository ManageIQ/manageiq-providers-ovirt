class ManageIQ::Providers::Redhat::Inventory::Parser::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Parser::NetworkManager
  def parse
    super
    cloud_tenants
  end

  def cloud_tenants
    #comment
    collector.tenants.each do |t|
      tenant = persister.cloud_tenants.find_or_build(t.id)
      tenant.name = t.name
      tenant.description = t.description
      tenant.enabled = t.enabled
      tenant.ems_ref = t.id
      tenant.parent = persister.cloud_tenants.lazy_find(t.try(:parent_id))
    end
  end
end
