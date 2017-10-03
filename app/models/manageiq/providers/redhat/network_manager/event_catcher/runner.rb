class ManageIQ::Providers::Redhat::NetworkManager::EventCatcher::Runner < ManageIQ::Providers::Openstack::NetworkManager::EventCatcher::Runner
  def add_openstack_queue(event)
    event_hash = ManageIQ::Providers::Redhat::NetworkManager::EventParser.event_to_hash(event, @cfg[:ems_id])
    EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
  end
end
