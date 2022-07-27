class ManageIQ::Providers::Ovirt::NetworkManager::EventCatcher < ::MiqEventCatcher
  include ManageIQ::Providers::Openstack::EventCatcherMixin

  require_nested :Runner

  def self.settings_name
    :event_catcher_ovirt_network
  end
end
