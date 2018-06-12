module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::ClusterCollections
  extend ActiveSupport::Concern

  # group :ems_clusters
  def add_ems_clusters
    add_collection(infra, :ems_clusters) do |builder|
      if targeted?
        builder.add_properties(:arel => manager.ems_clusters.where(:ems_ref => manager_refs))
      end
    end
  end

  # group :ems_clusters
  def add_resource_pools
    add_collection(infra, :resource_pools) do |builder|
      builder.add_properties(:arel => manager.resource_pools.where(:uid_ems => manager_refs.collect { |ref| "#{URI(ref).path.split('/').last}_respool" })) if targeted?
    end
  end
end
