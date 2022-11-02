describe ManageIQ::Providers::Ovirt::InfraManager::Vm do
  let(:ip_address) { '192.168.1.31' }
  let(:ems)  { FactoryBot.create(:ems_ovirt) }
  let(:host) { FactoryBot.create(:host_ovirt, :ext_management_system => ems) }
  let(:vm)   { FactoryBot.create(:vm_ovirt, :ext_management_system => ems, :host => host) }

  context "#supports?" do
    let(:power_state_on)        { "up" }
    let(:power_state_suspended) { "down" }

    context("with :start") do
      let(:state) { :start }
      include_examples "Vm operation is available when not powered on"
    end

    context("with :stop") do
      let(:state) { :stop }
      include_examples "Vm operation is available when powered on"
    end

    context("with :suspend") do
      let(:state) { :suspend }
      include_examples "Vm operation is available when powered on"
    end

    context("with :pause") do
      let(:state) { :pause }
      include_examples "Vm operation is not available"
    end

    context("with :shutdown_guest") do
      let(:state) { :shutdown_guest }
      include_examples "Vm operation is available when powered on"
    end

    context("with :standby_guest") do
      let(:state) { :standby_guest }
      include_examples "Vm operation is not available"
    end

    context("with :reboot_guest") do
      let(:state) { :reboot_guest }
      include_examples 'Vm operation is available when powered on'
    end

    context("with :reset") do
      let(:state) { :reset }
      include_examples "Vm operation is not available"
    end
  end

  context "supports?(:clone)" do
    let(:vm_ovirt) { ManageIQ::Providers::Ovirt::InfraManager::Vm.new }

    it "returns false" do
      expect(vm_ovirt.supports?(:clone)).to eq(false)
    end
  end

  context "#calculate_power_state" do
    it "returns suspended when suspended" do
      expect(described_class.calculate_power_state('suspended')).to eq('suspended')
    end

    it "returns on when up" do
      expect(described_class.calculate_power_state('up')).to eq('on')
    end

    it "returns down when off" do
      expect(described_class.calculate_power_state('down')).to eq('off')
    end
  end

  describe "#supports?(:reconfigure_disks)" do
    context "when vm has no storage" do
      let(:vm) { FactoryBot.create(:vm_ovirt, :storage => nil, :ext_management_system => nil) }

      it "does not support reconfigure disks" do
        expect(vm.supports?(:reconfigure_disks)).to be_falsey
      end
    end

    context "when vm has storage" do
      let(:storage) { FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ") }
      let(:vm) { FactoryBot.create(:vm_ovirt, :storage => storage, :ext_management_system => nil) }

      context "when vm has no provider" do
        it "does not support reconfigure disks" do
          expect(vm.supports?(:reconfigure_disks)).to be_falsey
        end
      end

      context "when vm has provider" do
        let(:ems_ovirt) { FactoryBot.create(:ems_ovirt) }
        let(:vm) { FactoryBot.create(:vm_ovirt, :storage => storage, :ext_management_system => ems_ovirt) }

        it "supports reconfigure disks" do
          expect(vm.supports?(:reconfigure_disks)).to be_truthy
        end
      end
    end
  end

  describe "#supports?(:publish)" do
    let(:ems) { FactoryBot.create(:ems_ovirt_with_authentication) }
    context "when vm has no storage" do
      let(:vm) { FactoryBot.create(:vm_ovirt, :storage => nil, :ext_management_system => nil) }

      it "does not support publish" do
        expect(vm.supports?(:publish)).to be_falsey
      end
    end

    context "when vm has no ems" do
      let(:storage) { FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ") }
      let(:vm) { FactoryBot.create(:vm_ovirt, :storage => storage, :ext_management_system => nil) }

      it "does not support publish" do
        expect(vm.supports?(:publish)).to be_falsey
      end
    end

    context "when vm is not in down state" do
      let(:storage) { FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ") }
      let(:vm) { FactoryBot.create(:vm_ovirt, :ext_management_system => ems, :storage => storage) }

      it "does not support publish" do
        allow(vm).to receive(:power_state).and_return("on")

        expect(vm.supports?(:publish)).to be_falsey
      end
    end

    context "when vm is down" do
      let(:storage) { FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ") }
      let(:vm) { FactoryBot.create(:vm_ovirt, :ext_management_system => ems, :storage => storage) }

      it "does support publish" do
        allow(vm).to receive(:power_state).and_return("off")

        expect(vm.supports?(:publish)).to be_truthy
      end
    end
  end

  describe "#supports?(:terminate)" do
    context "when connected to a provider" do
      it "returns true" do
        expect(vm.supports?(:terminate)).to be_truthy
      end
    end

    context "when not connected to a provider" do
      let(:archived_vm) { FactoryBot.create(:vm_ovirt) }

      it "returns false" do
        expect(archived_vm.supports?(:terminate)).to be_falsey
        expect(archived_vm.unsupported_reason(:terminate)).to eq("The VM is not connected to an active Provider")
      end
    end
  end

  describe "#unregister" do
    before do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryBot.create(:ems_ovirt_with_authentication, :zone => zone)
      @vm = FactoryBot.create(:vm_ovirt, :ext_management_system => @ems)
      @vm_proxy = double("OvirtSDK4::Vm.new")
      @vm_service = double("OvirtSDK4::Vm")
    end

    context "v4" do
      it "unregisters a vm via v4 api" do
        allow(@vm).to receive(:with_provider_object).and_yield(@vm_service)
        allow(@vm_service).to receive(:unregister).and_return(nil)

        @vm.raw_unregister
      end
    end
  end
end
