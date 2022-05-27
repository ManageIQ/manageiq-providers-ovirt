class ManageIQ::Providers::Redhat::InfraManager::Host < ::Host
  def provider_object(connection = nil)
    ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4.new(:ems => ext_management_system).get_host_proxy(self, connection)
  end

  def verify_credentials(auth_type = nil, options = {})
    raise MiqException::MiqHostError, "No credentials defined" if missing_credentials?(auth_type)
    if auth_type.to_s != 'ipmi' && os_image_name !~ /linux_*/
      raise MiqException::MiqHostError, "Logon to platform [#{os_image_name}] not supported"
    end
    case auth_type.to_s
    when 'ipmi' then verify_credentials_with_ipmi(auth_type)
    else
      verify_credentials_with_ssh(auth_type, options)
    end

    true
  end

  supports :quick_stats do
    unless ext_management_system.supports?(:quick_stats)
      unsupported_reason_add(:quick_stats, 'RHV API version does not support quick_stats')
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
    n_('Host (Redhat)', 'Hosts (Redhat)', number)
  end
end
