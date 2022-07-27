FactoryBot.define do
  factory :distributed_virtual_switch_ovirt, :class => 'ManageIQ::Providers::Ovirt::InfraManager::DistributedVirtualSwitch'
end

FactoryBot.define do
  factory :external_distributed_virtual_switch_ovirt, :class => 'ManageIQ::Providers::Ovirt::InfraManager::ExternalDistributedVirtualSwitch'
end

FactoryBot.define do
  factory :host_switch, :class => 'HostSwitch'
end
