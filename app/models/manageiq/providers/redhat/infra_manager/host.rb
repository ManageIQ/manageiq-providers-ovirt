class ManageIQ::Providers::Redhat::InfraManager::Host < ::Host
  def provider_object(connection = nil)
    ovirt_services_class = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Builder
                           .build_from_ems_or_connection(:ems => ext_management_system, :connection => connection)
    ovirt_services_class.new(:ems => ext_management_system).get_host_proxy(self, connection)
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
    unless ext_management_system.supports_quick_stats?
      unsupported_reason_add(:quick_stats, 'RHV API version does not support quick_stats')
    end
  end

  # The minimum supported version is 4.2.4, so we hard code it here.
  supports :conversion_host do
    version = ext_management_system.api_version
    if version.nil? || Gem::Version.new(version) < Gem::Version.new('4.2.4')
      unsupported_reason_add(:conversion_host, 'RHV API version does not support conversion_host')
    end
  end

  def validate_enter_maint_mode
    return inactive_provider_message unless has_active_ems?

    result = validate_power_state('on')
    return result unless result.nil?

    { :available => true, :message => nil }
  end

  def validate_exit_maint_mode
    return inactive_provider_message unless has_active_ems?

    result = validate_power_state('maintenance')
    return result unless result.nil?

    { :available => true, :message => nil }
  end

  def inactive_provider_message
    { :available => false, :message => _('The Host is not connected to an active provider') }
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
