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
        :full_data           => event,
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

  def self.parse_new_target(full_data, message, ems, event_type)
    folders = parse_new_folders(full_data.data_center)
    dc      = folders.detect { |f| f.kind_of?(Datacenter) }

    cluster = parse_new_cluster(ems, full_data.cluster, dc)
    rp      = parse_new_resource_pool(cluster)
    if template?(event_type)
      vm_data = full_data.template
      klass = 'ManageIQ::Providers::Redhat::InfraManager::Template'
    else
      vm_data = full_data.vm
      klass = 'ManageIQ::Providers::Redhat::InfraManager::Vm'
    end
    vm = parse_new_vm(ems, vm_data, dc, cluster, message, event_type)

    target_hash = {
        :vms            => [vm],
        :clusters       => [cluster],
        :resource_pools => [rp],
        :folders        => [*folders]
    }

    return target_hash, klass, {:uid_ems => vm[:uid_ems]}
  end

  def self.parse_new_folders(dc)
    vm_folder_hash = {
        :type    => 'ManageIQ::Providers::Redhat::InfraManager::Folder',
        :name    => 'vm',
        :uid_ems => "#{dc.id}_vm",
        :hidden  => true
    }

    host_folder_hash = {
        :type    => 'ManageIQ::Providers::Redhat::InfraManager::Folder',
        :name    => 'host',
        :uid_ems => "#{dc.id}_host",
        :hidden  => true
    }

    dc_ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(dc.href)
    dc_hash = {
        :type         => 'ManageIQ::Providers::Redhat::InfraManager::Datacenter',
        :ems_ref      => dc_ems_ref,
        :uid_ems      => dc.id,
        :ems_children => {:folders => [vm_folder_hash, host_folder_hash]}
    }

    [dc_hash, vm_folder_hash, host_folder_hash]
  end

  def self.parse_new_vm(ems, vm_data, datacenter, cluster, message, event_type)
    ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(vm_data.href)

    template = ems_ref.include?('/templates/')
    type     = template ? "ManageIQ::Providers::Redhat::InfraManager::Template" : "ManageIQ::Providers::Redhat::InfraManager::Vm"

    vm_id = vm_data.id
    vm_hash = {
        :type     => type,
        :ems_ref  => ems_ref,
        :uid_ems  => vm_id,
        :vendor   => "redhat",
        :name     => parse_target_name(message, event_type),
        :location => "#{vm_id}.ovf",
        :template => template,
    }

    vm_hash[:ems_cluster] = cluster
    cluster[:ems_children][:resource_pools].first[:ems_children][:vms] << vm_hash

    vm_folder = datacenter[:ems_children][:folders].detect { |f| f[:name] == 'vm' }
    vm_folder[:ems_children] = {:vms => [vm_hash]}

    vm_hash
  end

  def self.parse_new_cluster(ems, cluster_data, datacenter)
    cluster_ref  = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(cluster_data.href)
    cluster_name = ems.ovirt_services.cluster_name_href(cluster_ref)

    cluster_hash = {
        :ems_ref      => cluster_ref,
        :uid_ems      => cluster_data.id,
        :name         => cluster_name,
        :ems_children => {:resource_pools => []}
    }

    host_folder = datacenter[:ems_children][:folders].detect { |f| f[:name] == 'host' }
    host_folder[:ems_children] = {:clusters => [cluster_hash]}

    cluster_hash
  end

  def self.template?(event_type)
    event_type.include?("TEMPLATE")
  end

  def self.parse_target_name(message, event_type)
    case event_type
    when "NETWORK_ADD_VM_INTERFACE"
      # sample message: "Interface nic1 (VirtIO) was added to VM v5. (User: admin@internal-authz)"
      message.split(/\s/)[7][0...-1]
    when "NETWORK_INTERFACE_PLUGGED_INTO_VM"
      # sample message: "Network Interface nic1 (VirtIO) was plugged to VM v5. (User: admin@internal)"
      message.split(/\s/)[8][0...-1]
    when "USER_ADD_VM_TEMPLATE_FINISHED_SUCCESS"
      # sample message: "Creation of Template second_temp from VM second has been completed."
      message.split(/\s/)[3]
    when "USER_ADD_VM_TEMPLATE"
      # sample message: "Creation of Template temp3 from VM vm2 was initiated by admin@internal-authz."
      message.split(/\s/)[3]
    else
      # sample message: "VM v5 was created by admin@internal."
      message.split(/\s/)[1]
    end
  end

  def self.parse_new_resource_pool(cluster)
    rp_hash = {
        :name         => "Default for Cluster #{cluster[:name]}",
        :uid_ems      => "#{cluster[:uid_ems]}_respool",
        :is_default   => true,
        :ems_children => {:vms => []}
    }

    cluster[:ems_children][:resource_pools] << rp_hash

    rp_hash
  end
end
