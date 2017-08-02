class ManageIQ::Providers::Redhat::NetworkManager::RefreshWorker < ::MiqEmsRefreshWorker
  require_nested :Runner

  def self.ems_class
    ManageIQ::Providers::Redhat::NetworkManager
  end

  def self.settings_name
    :ems_refresh_worker_redhat_network
  end
end
