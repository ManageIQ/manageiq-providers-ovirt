class ManageIQ::Providers::Redhat::NetworkManager::EventCatcher < ::MiqEventCatcher
  require_nested :Runner

  def self.settings_name
    :event_catcher_redhat_network
  end
end
