module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::StoragedomainsCollections
  extend ActiveSupport::Concern

  # group :storagedomains
  def add_storages
    add_collection(infra, :storages) do |builder|
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            ::Storage.where(:ems_ref => references(:storagedomains))
          end
        )
      end
    end
  end
end
