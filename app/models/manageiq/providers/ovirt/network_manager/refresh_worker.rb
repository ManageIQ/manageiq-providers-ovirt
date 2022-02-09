class ManageIQ::Providers::Ovirt::NetworkManager::RefreshWorker < ::MiqEmsRefreshWorker
  require_nested :Runner

  def self.settings_name
    :ems_refresh_worker_ovirt_network
  end
end
