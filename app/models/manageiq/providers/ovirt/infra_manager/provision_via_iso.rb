class ManageIQ::Providers::Ovirt::InfraManager::ProvisionViaIso < ManageIQ::Providers::Ovirt::InfraManager::Provision
  include_concern 'Cloning'
  include_concern 'Configuration'
  include_concern 'StateMachine'
end
