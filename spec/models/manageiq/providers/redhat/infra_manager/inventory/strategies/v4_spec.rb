describe ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4 do
  before(:each) do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryBot.create(:ems_redhat, :zone => zone, :hostname => "localhost", :ipaddress => "localhost",
                              :port => 8443)
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "pass123"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
    allow(@ems).to(receive(:supported_api_versions).and_return([3, 4]))
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts, File.join('spec/vcr_cassettes/', described_class.name.underscore, 'collect_disks.yml'))
    end
    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  describe "#collect_vms" do
    it 'collects the disks properly' do
      inventory = described_class.new(:ems => @ems)
      inventory.instance_variable_set(:@connection, @ems.connect)
      vms = inventory.collect_vms
      vm1_disks = vms[0].disks
      expect(vm1_disks.count).to eq(1)
      expect(vm1_disks.first.id).to eq("e0001bb7-3e18-457d-af89-8e5b565cc84f")
      vm13_disks = vms[13].disks
      expect(vm13_disks.count).to eq(2)
      expect(vm13_disks.collect(&:id)).to match_array(%w(9a3e866c-4497-46df-801a-d1739c31c69d 1f702a46-6a95-46ce-a682-a3ff26dbcee3))
    end
  end
end
