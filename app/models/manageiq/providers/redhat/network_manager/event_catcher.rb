class ManageIQ::Providers::Redhat::NetworkManager::EventCatcher < ::MiqEventCatcher
  require_nested :Runner

  def self.ems_class
    ManageIQ::Providers::Redhat::NetworkManager
  end

  def self.settings_name
    :event_catcher_redhat_network
  end
end
