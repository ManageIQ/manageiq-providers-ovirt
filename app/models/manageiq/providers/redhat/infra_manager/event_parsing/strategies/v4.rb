module ManageIQ::Providers::Redhat::InfraManager::EventParsing::Strategies
  class V4 < ManageIQ::Providers::Redhat::InfraManager::EventParsing::Parser
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
      return location if dc.blank?

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
      dc      = folders.detect { |f| f[:type] == 'Datacenter' }

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
        :type    => 'EmsFolder',
        :name    => 'vm',
        :uid_ems => "#{dc.id}_vm",
        :hidden  => true
      }

      host_folder_hash = {
        :type    => 'EmsFolder',
        :name    => 'host',
        :uid_ems => "#{dc.id}_host",
        :hidden  => true
      }

      dc_ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(dc.href)
      dc_hash = {
        :type         => 'Datacenter',
        :ems_ref      => dc_ems_ref,
        :ems_ref_obj  => dc_ems_ref,
        :uid_ems      => dc.id,
        :ems_children => {:folders => [vm_folder_hash, host_folder_hash]}
      }

      [dc_hash, vm_folder_hash, host_folder_hash]
    end

    def self.parse_new_vm(ems, vm_data, datacenter, cluster, message, event_type)
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(vm_data.href)
      parser = ManageIQ::Providers::Redhat::InfraManager::Refresh::Parse::ParserBuilder.new(ems).build

      vm_hash = parser.create_vm_hash(ems_ref.include?('/templates/'), ems_ref, vm_data.id, parse_target_name(message, event_type))

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
        :ems_ref_obj  => cluster_ref,
        :uid_ems      => cluster_data.id,
        :name         => cluster_name,
        :ems_children => {:resource_pools => []}
      }

      host_folder = datacenter[:ems_children][:folders].detect { |f| f[:name] == 'host' }
      host_folder[:ems_children] = {:clusters => [cluster_hash]}

      cluster_hash
    end
  end
end
