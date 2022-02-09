class ManageIQ::Providers::Ovirt::InfraManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  require_nested :Runner
end
