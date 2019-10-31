class ManageIQ::Providers::Redhat::InfraManager::Cluster < ManageIQ::Providers::InfraManager::Cluster
  include_concern 'ClusterUpgrade'
end
