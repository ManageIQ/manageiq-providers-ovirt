module ManageIQ::Providers::Redhat::Inventory::Persister::Shared::InfraGroup::NetworksCollections
  extend ActiveSupport::Concern

  # group :networks
  def add_switches
    add_collection(infra, :switches) do |builder|
      if targeted?
        arel = ::Switch.where(:uid_ems => manager_refs) if manager_refs.present?

        builder.add_properties(:arel => arel) unless arel.nil?
      end
    end
  end
end
