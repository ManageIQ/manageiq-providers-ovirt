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
    vlans = []

    switch_ids = HostSwitch.where(:host => host).pluck(:switch_id)
    Lan.where(:switch_id => switch_ids).each do |lan|
      vlans << lan.name
    end

    vlans.sort.concat(available_external_vlans)
  end

  def available_external_vlans
    ext_vlans = []
    ems = ext_management_system

    ext_switch_ids = ems.external_distributed_virtual_switches.pluck(:id)
    ems.external_distributed_virtual_lans.where(:switch_id => ext_switch_ids).each do |ext_lan|
      ext_vlans << "#{ext_lan.name}/#{ext_lan.switch.name}"
    end

    ext_vlans.sort
  end

  def build_config_spec(task_options)
    {
      "numCoresPerSocket" => (task_options[:cores_per_socket].to_i if task_options[:cores_per_socket]),
      "memoryMB"          => (task_options[:vm_memory].to_i if task_options[:vm_memory]),
      "numCPUs"           => (task_options[:number_of_cpus].to_i if task_options[:number_of_cpus]),
      "disksRemove"       => task_options[:disk_remove],
      "disksAdd"          => (spec_for_added_disks(task_options[:disk_add]) if task_options[:disk_add])
    }
  end

  def spec_for_added_disks(disks)
    {
      :disks   => disks,
      :storage => storage
    }
  end
end
