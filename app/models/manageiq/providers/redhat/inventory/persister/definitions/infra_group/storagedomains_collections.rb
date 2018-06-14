module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::StoragedomainsCollections
  extend ActiveSupport::Concern

  # group :storagedomains
  def add_storages
    add_collection(infra, :storages) do |builder|
      if targeted?
        arel = ::Storage.where(:ems_ref => manager_refs) if manager_refs.present?

        builder.add_properties(:arel => arel) unless arel.nil?
      end
    end
  end
end
