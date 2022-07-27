module ManageIQ::Providers::Ovirt::InfraManager::SnapshotDisksMixin
  def disks_total_size(connection, vm_id)
    return nil if active_vm_snapshot?

    vm_service = connection.system_service.vms_service.vm_service(vm_id)
    snapshot_service = vm_service.snapshots_service.snapshot_service(id)
    snapshot_service.disks_service.list.sum(&:actual_size)
  end

  def active_vm_snapshot?
    description == "Active VM"
  end
end
