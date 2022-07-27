module ManageIQ::Providers::Ovirt::Inventory::Persister::Definitions::NetworkCollections
  extend ActiveSupport::Concern

  # ------ IC provider specific definitions -------------------------

  def add_cloud_tenants
    add_collection(network, :cloud_tenants) do |builder|
      builder.add_properties(
        :model_class => ManageIQ::Providers::Openstack::CloudManager::CloudTenant
      )
      builder.add_default_values(
        :ems_id => manager.parent_manager.try(:id) # changed from :ext_management_system
      )
    end
  end

  def add_guest_devices
    add_collection(infra,
                   :guest_devices,
                   :strategy       => :local_db_cache_all,
                   :secondary_refs => {:by_uid_ems => %i[uid_ems]})
  end
end
