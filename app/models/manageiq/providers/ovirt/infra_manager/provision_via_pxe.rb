class ManageIQ::Providers::Ovirt::InfraManager::ProvisionViaPxe < ManageIQ::Providers::Ovirt::InfraManager::Provision
  include Cloning
  include Configuration
  include StateMachine
end
