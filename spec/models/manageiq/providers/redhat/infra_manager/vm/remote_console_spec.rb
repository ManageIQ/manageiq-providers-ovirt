describe ManageIQ::Providers::Redhat::InfraManager::Vm::RemoteConsole do
  let(:user) { FactoryBot.create(:user) }
  let(:ems) { FactoryBot.create(:ems_redhat) }
  let(:vm) { FactoryBot.create(:vm_redhat, :ext_management_system => ems) }

  context '#console_supported?' do
    it 'html5 disabled in settings' do
      ::Settings.ems.ems_redhat.consoles.html5_enabled = false

      expect(vm.console_supported?('spice')).to be false
      expect(vm.console_supported?('vnc')).to be false
      expect(vm.console_supported?('native')).to be true
    end

    it 'html5 enabled in settings' do
      ::Settings.ems.ems_redhat.consoles.html5_enabled = true

      expect(vm.console_supported?('spice')).to be true
      expect(vm.console_supported?('vnc')).to be true
      expect(vm.console_supported?('native')).to be true
    end
  end

  context '#validate_remote_console_acquire_ticket' do
    it 'no errors for html5 console enabled' do
      ::Settings.ems.ems_redhat.consoles.html5_enabled = true

      expect { vm.validate_remote_console_acquire_ticket('html5') }.not_to raise_error
    end

    context 'errors' do
      it 'html5 disabled by default in settings' do
        ::Settings.ems.ems_redhat.consoles.html5_enabled = false

        expect { vm.validate_remote_console_acquire_ticket('html5') }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError,
                          /Html5 console is disabled by default/)
      end

      it 'vm with no ems' do
        ::Settings.ems.ems_redhat.consoles.html5_enabled = true
        vm.update_attribute(:ext_management_system, nil)

        expect { vm.validate_remote_console_acquire_ticket('html5') }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /registered with a management system/)
      end

      it 'vm not running' do
        ::Settings.ems.ems_redhat.consoles.html5_enabled = true
        vm.update_attribute(:raw_power_state, 'poweredOff')

        expect { vm.validate_remote_console_acquire_ticket('html5') }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /vm to be running/)
      end
    end
  end
end
