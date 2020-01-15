FactoryBot.define do
  factory :distributed_virtual_switch_redhat, :class => 'ManageIQ::Providers::Redhat::InfraManager::DistributedVirtualSwitch'
end

FactoryBot.define do
  factory :external_distributed_virtual_switch_redhat, :class => 'ManageIQ::Providers::Redhat::InfraManager::ExternalDistributedVirtualSwitch'
end

FactoryBot.define do
  factory :host_switch, :class => 'HostSwitch'
end
