class ManageIQ::Providers::Redhat::NetworkManager::RefreshWorker < ::MiqEmsRefreshWorker
  require_nested :Runner

  def self.settings_name
    :ems_refresh_worker_redhat_network
  end
end
