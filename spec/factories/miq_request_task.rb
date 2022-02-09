FactoryBot.define do
  factory :miq_provision_ovirt_via_iso, :parent => :miq_provision_ovirt, :class => "ManageIQ::Providers::Ovirt::InfraManager::ProvisionViaIso"
  factory :miq_provision_ovirt_via_pxe, :parent => :miq_provision_ovirt, :class => "ManageIQ::Providers::Ovirt::InfraManager::ProvisionViaPxe"
end
