module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::DatacentersCollections
  extend ActiveSupport::Concern

  # group :datacenters
  def add_datacenters
    add_collection(infra, :datacenters) do |builder|
      builder.add_properties(:arel => manager.ems_folders.where(:type => 'Datacenter'))

      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.ems_folders.where(:type => 'Datacenter').where(:ems_ref => references(:datacenters))
          end
        )
      end
    end
  end
end
