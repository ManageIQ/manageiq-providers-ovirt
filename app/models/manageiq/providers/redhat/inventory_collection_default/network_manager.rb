class ManageIQ::Providers::Redhat::InventoryCollectionDefault::NetworkManager < ManageIQ::Providers::Openstack::InventoryCollectionDefault::NetworkManager
  class << self
    def cloud_tenants(extra_attributes = {})
      attributes = {
          :model_class                 => ManageIQ::Providers::Openstack::CloudManager::CloudTenant,
          :association                 => :cloud_tenants,
          :inventory_object_attributes => [
              :type,
              :name,
              :description,
              :enabled,
              :parent,
              :ems_ref
          ]
      }
      attributes.merge!(extra_attributes)
    end
  end
end
