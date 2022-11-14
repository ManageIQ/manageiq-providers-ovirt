FactoryBot.define do
  factory :iso_datastore, :class => 'ManageIQ::Providers::Ovirt::InfraManager::IsoDatastore', :parent => :storage_redhat
end
