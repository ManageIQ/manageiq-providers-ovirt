class ManageIQ::Providers::Ovirt::InfraManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner
  # might need to set settings name here
end
