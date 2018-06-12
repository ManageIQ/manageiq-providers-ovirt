module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::DatacentersCollections
  extend ActiveSupport::Concern

  # group :datacenters
  def add_datacenters
    add_collection(infra, :datacenters) do |builder|
      arel = if targeted?
               manager.ems_folders.where(:type => 'Datacenter').where(:ems_ref => manager_refs) if manager_refs.present?
             else
               manager.ems_folders.where(:type => 'Datacenter')
             end

      builder.add_properties(:arel => arel) unless arel.nil?
    end
  end
end
