module ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations::Snapshot
  extend ActiveSupport::Concern

  included do
    supports :snapshots do
      if supports?(:control)
        unless ext_management_system.supports?(:snapshots)
          unsupported_reason_add(:snapshots, ext_management_system.unsupported_reason(:snapshots))
        end
      else
        unsupported_reason_add(:snapshots, unsupported_reason(:control))
      end
    end

    supports :revert_to_snapshot do
      unless allowed_to_revert?
        unsupported_reason_add(:revert_to_snapshot, revert_unsupported_message)
      end
    end

    supports_not :remove_all_snapshots, :reason => N_("Removing all snapshots is currently not supported")
  end

  def raw_create_snapshot(_name, desc, memory)
    with_snapshots_service(uid_ems) do |snapshots_service|
      snapshots_service.add(:description => desc, :persist_memorystate => memory)
    end
  end

  def raw_remove_snapshot(snapshot_id)
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to remove snapshot") unless snapshot
    with_snapshots_service(uid_ems) do |snapshots_service|
      snapshots_service.snapshot_service(snapshot.uid_ems).remove
    end
  end

  def raw_revert_to_snapshot(snapshot_id)
    snapshot = snapshots.find_by(:id => snapshot_id)
    raise _("Requested VM snapshot not found, unable to RevertTo snapshot") unless snapshot
    with_snapshots_service(uid_ems) do |snapshots_service|
      snapshots_service.snapshot_service(snapshot.uid_ems).restore
    end
  end

  def snapshot_name_optional?
    true
  end

  def snapshot_description_required?
    true
  end

  def allowed_to_revert?
    current_state == 'off'
  end

  def revert_to_snapshot_denied_message(active = false)
    return revert_unsupported_message unless allowed_to_revert?
    return _("Revert is not allowed for a snapshot that is the active one") if active
  end

  def remove_snapshot_denied_message(active = false)
    return _("Delete is not allowed for a snapshot that is the active one") if active
  end

  def snapshotting_memory_allowed?
    current_state == 'on'
  end

  private

  def revert_unsupported_message
    _("Revert is allowed only when vm is down. Current state is %{state}") % {:state => current_state}
  end

  def with_snapshots_service(vm_uid_ems)
    connection = ext_management_system.connect(:version => 4)
    service = connection.system_service.vms_service.vm_service(vm_uid_ems).snapshots_service
    yield service
  end
end
