FactoryGirl.define do
  factory :ems_cluster_redhat, :class => "ManageIQ::Providers::Redhat::InfraManager::EmsCluster", :parent => :ems_cluster
end
