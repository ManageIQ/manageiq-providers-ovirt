module ManageIQ::Providers::Redhat::InfraManager::EventParser
  # Sample RHV Event
  #
  # :id: '13060729'
  # :href: /api/events/13060729
  # :cluster:
  #   :id: 40c1c666-e919-11e0-9c6b-005056af0085
  #   :href: /api/clusters/40c1c666-e919-11e0-9c6b-005056af0085
  # :host:
  #   :id: ca389dbc-2054-11e1-9241-005056af0085
  #   :href: /api/hosts/ca389dbc-2054-11e1-9241-005056af0085
  # :template:
  #   :id: 7120b19a-1b39-4bd4-afa8-6393fc4cd3dc
  #   :href: /api/templates/7120b19a-1b39-4bd4-afa8-6393fc4cd3dc
  # :user:
  #   :id: 97aca95a-72d4-4882-bf31-e2832ce3a0ba
  #   :href: /api/users/97aca95a-72d4-4882-bf31-e2832ce3a0ba
  # :vm:
  #   :id: b79de892-655a-455d-b926-4dd620bc1fd4
  #   :href: /api/vms/b79de892-655a-455d-b926-4dd620bc1fd4
  # :description: ! 'VM shutdown initiated by bdunne on VM bd-s (Host: rhelvirt.manageiq.com).'
  # :severity: normal
  # :code: 73
  # :time: 2012-08-17 12:01:25.555000000 -04:00
  # :name: USER_INITIATED_SHUTDOWN_VM

  def self.event_to_hash(event, ems_id = nil)
    log_header = "ems_id: [#{ems_id}] " unless ems_id.nil?

    _log.debug { "#{log_header}event: [#{event.inspect}]" }

    # Connect back to RHEV to get the actual user_name
    ems       = ManageIQ::Providers::Redhat::InfraManager.find_by(:id => ems_id)
    user_href = ems_ref_from_object_in_event(event.user)
    username  = nil
    if ems && user_href
      username = ems.ovirt_services.username_by_href(user_href)
    end

    vm_ref = template?(event.name) ? ems_ref_from_object_in_event(event.template) : ems_ref_from_object_in_event(event.vm)

    # Build the event hash
    hash = {
        :event_type          => event.name,
        :source              => 'RHEVM',
        :message             => event.description,
        :timestamp           => event.time,
        :username            => username,
        :full_data           => ovirtobj_to_hash(event),
        :ems_id              => ems_id,
        :vm_ems_ref          => vm_ref,
        :host_ems_ref        => ems_ref_from_object_in_event(event.host),
        :ems_cluster_ems_ref => ems_ref_from_object_in_event(event.cluster),
    }

    add_vm_location(hash, event.data_center, vm_ref)
  end

  def self.add_vm_location(hash, dc, vm_ref)
    return hash if vm_ref.nil?

    uid_ems = ManageIQ::Providers::Redhat::InfraManager.extract_ems_ref_id(vm_ref)
    location = "#{uid_ems}.ovf"
    if dc.blank?
      hash[:vm_location] = location
      return hash
    end
    dc_ref = ems_ref_from_object_in_event(dc)
    dc_uid = ManageIQ::Providers::Redhat::InfraManager.extract_ems_ref_id(dc_ref)

    hash[:vm_location] = File.join('/rhev/data-center', dc_uid, 'mastersd/master/vms', uid_ems, location)
    hash
  end

  def self.ems_ref_from_object_in_event(data)
    return nil unless data && data.href
    ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(data.href)
  end

  def self.template?(event_type)
    event_type.include?("TEMPLATE")
  end

  def self.ovirtobj_to_hash(obj)
    obj.instance_variables.each_with_object({}) do |k, h|
      val = obj.instance_variable_get(k)

      h[k.to_s[1..-1]] = case val
                         when OvirtSDK4::Identified
                           ovirtobj_to_hash(val)
                         when Array
                           val.map { |v| ovirtobj_to_hash(v) }
                         else
                           val.to_s
                         end
    end
  end
end
