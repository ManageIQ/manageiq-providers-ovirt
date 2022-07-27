module ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations::Configuration
  extend ActiveSupport::Concern

  def raw_set_memory(mb)
    run_command_via_parent(:vm_set_memory, :value => mb)
  end

  def raw_set_number_of_cpus(num)
    run_command_via_parent(:vm_set_num_cpus, :value => num)
  end

  def raw_add_disk(disk_name, disk_size_mb, options = {})
    if options[:datastore]
      datastore = ext_management_system.hosts.collect do |h|
        h.writable_accessible_storages.find_by(:name => options[:datastore])
      end.uniq.compact.first
      raise _("Datastore does not exist or cannot be accessed, unable to add disk") unless datastore
    end

    run_command_via_parent(:vm_add_disk, :diskName => disk_name, :diskSize => disk_size_mb,
        :thinProvisioned => options[:thin_provisioned], :dependent => options[:dependent],
        :persistent => options[:persistent], :bootable => options[:bootable], :datastore => datastore,
        :interface => options[:interface])
  end

  def raw_reconfigure(spec)
    run_command_via_parent(:vm_reconfigure, :spec => spec)
  end
end
