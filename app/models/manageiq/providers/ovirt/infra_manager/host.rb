class ManageIQ::Providers::Ovirt::InfraManager::Host < ::Host
  def provider_object(connection = nil)
    ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::V4.new(:ems => ext_management_system).get_host_proxy(self, connection)
  end

  supports :capture
  supports :quick_stats do
    unless ext_management_system.supports?(:quick_stats)
      unsupported_reason_add(:quick_stats, 'oVirt API version does not support quick_stats')
    end
  end

  supports :enter_maint_mode do
    unsupported_reason_add(:enter_maint_mode, _('The Host is not connected to an active provider')) unless has_active_ems?
    unsupported_reason_add(:enter_maint_mode, _('The Host is not powered on')) unless power_state == 'on'
  end

  supports :exit_maint_mode do
    unsupported_reason_add(:enter_maint_mode, _('The Host is not connected to an active provider')) unless has_active_ems?
    unsupported_reason_add(:enter_maint_mode, _('The Host is not in maintenance mode')) unless power_state == 'maintenance'
  end

  def enter_maint_mode
    ext_management_system.ovirt_services.host_deactivate(self)
  end

  def exit_maint_mode
    ext_management_system.ovirt_services.host_activate(self)
  end

  def self.display_name(number = 1)
    n_('Host (oVirt)', 'Hosts (oVirt)', number)
  end
end
