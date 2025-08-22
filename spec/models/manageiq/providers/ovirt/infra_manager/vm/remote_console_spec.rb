describe ManageIQ::Providers::Ovirt::InfraManager::Vm::RemoteConsole do
  let(:user) { FactoryBot.create(:user) }
  let(:ems) { FactoryBot.create(:ems_ovirt) }
  let(:vm) { FactoryBot.create(:vm_ovirt, :ext_management_system => ems) }


  it '#native_console_connection_queue' do
    vm.native_console_connection_queue(user.userid)

    queue_messages = MiqQueue.all
    expect(queue_messages.length).to eq(1)
    expect(queue_messages.first.method_name).to eq('native_console_connection')
    expect(queue_messages.first.args).to be_empty
  end

  context '#supports?(:console)' do
    it 'html5 disabled in settings' do
      stub_html5_enable(false)

      expect(vm.supports?(:spice_console)).to be false
      expect(vm.supports?(:vnc_console)).to be false
      expect(vm.supports?(:html5_console)).to be false
      expect(vm.supports?(:console)).to be false
      expect(vm.supports?(:native_console)).to be true
    end

    it 'html5 enabled in settings' do
      stub_html5_enable(true)

      expect(vm.supports?(:spice_console)).to be true
      expect(vm.supports?(:vnc_console)).to be true
      expect(vm.supports?(:native_console)).to be true
      expect(vm.supports?(:html5_console)).to be true
      expect(vm.supports?(:console)).to be true
    end
  end

  context '#validate_remote_console_acquire_ticket' do
    it 'no errors for html5 console enabled' do
      stub_html5_enable(true)

      expect { vm.validate_remote_console_acquire_ticket('html5') }.not_to raise_error
    end

    context 'errors' do
      it 'html5 disabled by default in settings' do
        stub_html5_enable(false)

        expect { vm.validate_remote_console_acquire_ticket('html5') }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError,
                          /Html5 console is disabled by default/)
      end

      it 'vm with no ems' do
        stub_html5_enable(true)
        vm.update_attribute(:ext_management_system, nil)

        expect { vm.validate_remote_console_acquire_ticket('html5') }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /registered with a management system/)
      end

      it 'vm not running' do
        stub_html5_enable(true)
        vm.update_attribute(:raw_power_state, 'poweredOff')

        expect { vm.validate_remote_console_acquire_ticket('html5') }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /vm to be running/)
      end
    end
  end

  context '#validate_native_console_support' do
    it 'no errors for the normal situation' do
      expect { vm.validate_native_console_support }.not_to raise_error
    end

    context 'errors' do
      it 'vm with no ems' do
        vm.update_attribute(:ext_management_system, nil)

        expect { vm.validate_native_console_support }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /registered with a management system/)
      end

      it 'vm not running' do
        vm.update_attribute(:raw_power_state, 'poweredOff')

        expect { vm.validate_native_console_support }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /vm to be running/)
      end
    end
  end

  context '#native_console_connection' do
    let(:graphics_consoles_service) { double('GraphicsConsolesService') }
    let(:console_service) { double('ConsoleService') }
    let(:vm_service) { double('VmService', :graphics_consoles_service => graphics_consoles_service) }
    let(:fake_connection) { 'fake connection content' }

    before(:each) do
      allow(vm).to receive(:with_provider_object).and_yield(vm_service)
      allow(graphics_consoles_service).to receive(:list).with(:current => true).and_return(consoles)
    end

    context 'headless' do
      let(:consoles) { [] }

      it 'no consoles available' do
        expect { vm.native_console_connection }
          .to raise_error(MiqException::RemoteConsoleNotSupportedError, /No remote native console available for this vm/)
      end
    end

    context 'one console' do
      let(:consoles) { [double('VncConsole', :id => '7370696365', :protocol => 'vnc')] }

      it 'connection for the only console' do
        expect(graphics_consoles_service).to receive(:console_service).with(consoles.first.id).and_return(console_service)
        expect(console_service).to receive(:remote_viewer_connection_file).and_return(fake_connection)

        res = vm.native_console_connection

        expect(res).to include(
          :connection => Base64.encode64(fake_connection),
          :type       => 'application/x-virt-viewer',
          :name       => 'console.vv'
        )
      end
    end

    context 'more then one console' do
      let(:vnc_console) { double('VncConsole', :id => '7370696365', :protocol => 'vnc') }
      let(:spice_console) { double('SpiceConsole', :id => '9998465674', :protocol => 'spice') }
      let(:consoles) { [vnc_console, spice_console] }

      it 'select the spice console for connection' do
        expect(graphics_consoles_service).to receive(:console_service).with(spice_console.id).and_return(console_service)
        expect(console_service).to receive(:remote_viewer_connection_file).and_return(fake_connection)

        res = vm.native_console_connection

        expect(res).to include(
          :connection => Base64.encode64(fake_connection),
          :type       => 'application/x-virt-viewer',
          :name       => 'console.vv'
        )
      end
    end
  end

  private

  # @param value [Boolean] whether html5 is enabled
  def stub_html5_enable(value)
    stub_settings_merge(:ems => {:ems_ovirt => {:consoles => {:html5_enabled => value}}})
  end
end
