module ManageIQ::Providers::Redhat::InfraManager::Vm::Reconfigure
  # Show Reconfigure VM task
  def reconfigurable?
    active?
  end

  def max_total_vcpus
    # the default value of MaxNumOfVmCpusTotal for RHEV 3.1 - 3.4
    160
  end

  def max_cpu_cores_per_socket
    # the default value of MaxNumOfCpuPerSocket for RHEV 3.1 - 3.4
    16
  end

  def max_vcpus
    # the default value of MaxNumofVmSockets for RHEV 3.1 - 3.4
    16
  end

  def max_memory_mb
    2.terabyte / 1.megabyte
  end

  def available_vlans
    vlans = host.lans.pluck(:name)

    vlans.sort.concat(available_external_vlans)
  end

  def available_external_vlans
    ext_vlans = parent_datacenter.external_distributed_virtual_lans.map { |lan| "#{lan.name}/#{lan.switch.name}" }

    ext_vlans.sort
  end

  def build_config_spec(task_options)
    {
      "numCoresPerSocket" => (task_options[:cores_per_socket].to_i if task_options[:cores_per_socket]),
      "memoryMB"          => (task_options[:vm_memory].to_i if task_options[:vm_memory]),
      "numCPUs"           => (task_options[:number_of_cpus].to_i if task_options[:number_of_cpus]),
      "disksRemove"       => task_options[:disk_remove],
      "disksAdd"          => (spec_for_added_disks(task_options[:disk_add]) if task_options[:disk_add]),
      "networkAdapters"   => spec_for_network_adapters(task_options)
    }
  end

  def spec_for_added_disks(disks)
    {
      :disks   => disks,
      :storage => storage
    }
  end

  def spec_for_network_adapters(options)
    {
      :edit   => (network_adapters_edit(options[:network_adapter_edit]) if options[:network_adapter_edit]),
      :add    => (network_adapters_add(options[:network_adapter_add]) if options[:network_adapter_add]),
      :remove => (network_adapters_remove(options[:network_adapter_remove]) if options[:network_adapter_remove])
    }.compact
  end

  def network_adapters_add(adapters)
    nic_names = hardware.nics.pluck(:device_name)
    switch_ids = HostSwitch.where(:host => host).pluck(:switch_id)

    adapters.collect do |adapt|
      new_nic_name = suggest_nic_name(nic_names)
      nic_names << new_nic_name
      network_adapter_add_spec(adapt['network'],
                               new_nic_name,
                               switch_ids)
    end
  end

  def network_adapters_edit(adapters)
    switch_ids = HostSwitch.where(:host => host).pluck(:switch_id)

    adapters.collect do |adapt|
      network_adapter_edit_spec(adapt['network'],
                                adapt['name'],
                                switch_ids)
    end
  end

  def network_adapters_remove(adapters)
    adapters.collect do |adapt|
      network_adapter_remove_spec(adapt['network']['vlan'],
                                  adapt['network']['name'],
                                  adapt['network']['mac'])
    end
  end

  def network_adapter_add_spec(network_name, nic_name, switch_ids)
    lan = find_lan_by_name(network_name, switch_ids)
    raise MiqException::MiqVmError, "Network [#{network_name}] not available for the target" unless lan

    {
      :network         => network_name,
      :name            => nic_name,
      :vnic_profile_id => lan.uid_ems
    }
  end

  def network_adapter_edit_spec(network_name, nic_name, switch_ids)
    nic = hardware.nics.find_by(:name => nic_name)
    raise MiqException::MiqVmError, "No NIC named '#{nic_name}' was found" unless nic

    lan = find_lan_by_name(network_name, switch_ids)
    raise MiqException::MiqVmError, "Network [#{network_name}] not available for the target" unless lan

    {
      :network         => network_name,
      :name            => nic_name,
      :vnic_profile_id => lan.uid_ems,
      :nic_id          => nic.uid_ems
    }
  end

  def network_adapter_remove_spec(network_name, nic_name, mac)
    nic = hardware.nics.find_by(:name => nic_name)
    raise MiqException::MiqVmError, "No NIC named '#{nic_name}' was found" unless nic

    {
      :network     => network_name,
      :name        => nic_name,
      :mac_address => mac,
      :nic_id      => nic.uid_ems
    }
  end

  def find_lan_by_name(network_name, switch_ids)
    lan_name, ext_switch_name = network_name.split('/').collect(&:strip)

    switch_ids = ext_switch_ids_by_name(ext_switch_name) if ext_switch_name

    Lan.find_by(:name => lan_name, :switch_id => switch_ids)
  end

  def ext_switch_ids_by_name(switch_name)
    parent_datacenter.external_distributed_virtual_switches.select { |s| s.name == switch_name }.map(&:id)
  end

  def suggest_nic_name(nic_list)
    nic_list.inject('nic1') do |memo, n|
      m = n.match(/^nic(\d+)$/)
      next memo unless m

      nic_number = m[1].to_i + 1
      nic_number > memo[3..-1].to_i ? "nic#{nic_number}" : memo
    end
  end
end
