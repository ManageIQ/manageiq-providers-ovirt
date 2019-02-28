module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::ClusterCollections
  extend ActiveSupport::Concern

  def add_ems_clusters
    add_collection(infra, :ems_clusters) do |builder|
      builder.add_properties(
        :secondary_refs => {:by_uid_ems => %i(uid_ems)}
      )
    end
  end

  # group :ems_clusters
  def add_resource_pools
    add_collection(infra, :resource_pools) do |builder|
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.resource_pools.where(:uid_ems => references(:ems_clusters).collect { |ref| "#{URI(ref).path.split('/').last}_respool" })
          end
        )
      end
    end
  end
end
