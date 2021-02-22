class ManageIQ::Providers::Redhat::Inventory::Parser::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Parser::NetworkManager
  def parse
    super
    cloud_tenants
    cloud_networks
    cloud_subnets
    network_routers
    security_groups
  end

  def cloud_tenants
    collector.tenants.each do |t|
      tenant = persister.cloud_tenants.find_or_build(t.id)
      tenant.name = t.name
      tenant.description = t.description
      tenant.enabled = t.enabled
      tenant.ems_ref = t.id
      tenant.parent = persister.cloud_tenants.lazy_find(t.try(:parent_id))
    end
  end

  def cloud_networks
    collector.cloud_networks.each do |n|
      tenant = cloud_tenant_mapper(n["name"])
      network.cloud_tenant = tenant || persister.cloud_tenants.lazy_find(n["tenant_id"])
    end
  end

  def cloud_subnets
    collector.cloud_subnets.each do |s|
      tenant = cloud_tenant_mapper(s.name)
      subnet.cloud_tenant = tenant || persister.cloud_tenants.lazy_find(s.tenant_id)
    end
  end

  def network_routers
    collector.network_routers.each do |nr|
      tenant = cloud_tenant_mapper(nr.name)
      network_router.cloud_tenant = tenant || persister.cloud_tenants.lazy_find(nr.tenant_id)
    end
  end

  def security_groups
    collector.security_groups.each do |s|
      tenant = cloud_tenant_mapper(s.name)
      security_group.cloud_tenant = tenant || persister.cloud_tenants.lazy_find(s.tenant_id)
    end
  end

  def find_device_object(network_port)
    super || find_ovirt_device_object(network_port)
  end

  private

  def find_ovirt_device_object(network_port)
    nil unless network_port.device_owner&.downcase == 'ovirt'

    persister.guest_devices.lazy_find({:uid_ems => network_port.device_id}, {:ref => :by_uid_ems})
  end

  def cloud_tenant_mapper(name)
    name_parts = name.split(::Settings.ems.ems_ovirt.cloud_tenant_mapper.separator)
    CloudTenant.find_by(:name => name_parts[::Settings.ems.ems_ovirt.cloud_tenant_mapper.tenant])
  end
end
