module ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations::Guest
  extend ActiveSupport::Concern

  included do
    supports :shutdown_guest do
      if current_state == "on"
        unsupported_reason(:control)
      else
        _("The VM is not powered on")
      end
    end

    supports :reboot_guest do
      if current_state == "on"
        unsupported_reason(:control)
      else
        _("The VM is not powered on")
      end
    end
  end

  def raw_shutdown_guest
    ext_management_system.ovirt_services.shutdown_guest(self)
  end

  def raw_reboot_guest
    ext_management_system.ovirt_services.reboot_guest(self)
  end
end
