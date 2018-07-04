module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::NetworksCollections
  extend ActiveSupport::Concern

  # group :networks
  def add_switches
    add_collection(infra, :switches) do |builder|
      if targeted?
        # TODO are switches shared across emses? Seems like we weren't filling ems_id
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            ::Switch.where(:uid_ems => references(:networks))
          end
        )
      end
    end
  end
end
