class ManageIQ::Providers::Ovirt::InfraManager::ProvisionViaIso < ManageIQ::Providers::Ovirt::InfraManager::Provision
  include Cloning
  include Configuration
  include StateMachine
end
