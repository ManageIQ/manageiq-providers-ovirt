module ManageIQ::Providers::Redhat::Inventory::Persister::Shared::NetworkCollections
  extend ActiveSupport::Concern

  # ------ IC provider specific definitions -------------------------

  def add_cloud_tenants
    add_collection(network, :cloud_tenants) do |builder|
      builder.add_properties(
        :model_class => ManageIQ::Providers::Openstack::CloudManager::CloudTenant
      )
      builder.add_builder_params(
        :ext_management_system => manager.parent_manager
      )
    end
  end
end
