module ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations::Power
  extend ActiveSupport::Concern
  included do
    supports_not :pause, :reason => "Pause Operation is not available for oVirt/RHV VMs"
  end

  def raw_start
    start_with_cloud_init = custom_attributes.find_by(:name => "miq_provision_boot_with_cloud_init")
    start_with_sysprep = custom_attributes.find_by(:name => "miq_provision_boot_with_sysyprep")
    if start_with_cloud_init
      ext_management_system.ovirt_services.vm_start(self, :use_cloud_init => start_with_cloud_init)
      start_with_cloud_init.try(&:destroy)
    elsif start_with_sysprep
      ext_management_system.ovirt_services.vm_start(self, :use_sysprep => start_with_sysprep)
      start_with_sysprep.try(&:destroy)
    else
      ext_management_system.ovirt_services.vm_start(self, {})
    end
  end

  def raw_stop
    ext_management_system.ovirt_services.vm_stop(self)
  end

  def raw_suspend
    ext_management_system.ovirt_services.vm_suspend(self)
  end
end
