class ManageIQ::Providers::Ovirt::Inventory::Parser::NetworkManager < ManageIQ::Providers::Openstack::Inventory::Parser::NetworkManager
  def parse
    super
    cloud_tenants
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

  def find_device_object(network_port)
    super || find_ovirt_device_object(network_port)
  end

  private

  def find_ovirt_device_object(network_port)
    nil unless network_port.device_owner&.downcase == 'ovirt'

    persister.guest_devices.lazy_find({:uid_ems => network_port.device_id}, :ref => :by_uid_ems)
  end
end
