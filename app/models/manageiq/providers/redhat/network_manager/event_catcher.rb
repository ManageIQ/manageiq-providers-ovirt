class ManageIQ::Providers::Redhat::NetworkManager::EventCatcher < ::MiqEventCatcher
  include ManageIQ::Providers::Openstack::EventCatcherMixin

  require_nested :Runner

  def self.settings_name
    :event_catcher_redhat_network
  end
end
