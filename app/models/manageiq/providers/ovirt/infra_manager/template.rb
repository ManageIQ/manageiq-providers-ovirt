class ManageIQ::Providers::Ovirt::InfraManager::Template < ManageIQ::Providers::InfraManager::Template
  include ManageIQ::Providers::Ovirt::InfraManager::VmOrTemplateShared

  supports :provisioning do
    if ext_management_system
      ext_management_system.unsupported_reason(:provisioning)
    else
      _('not connected to ems')
    end
  end

  supports :kickstart_provisioning

  def provider_object(connection = nil)
    ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::V4.new(:ems => ext_management_system).get_template_proxy(self, connection)
  end
end
