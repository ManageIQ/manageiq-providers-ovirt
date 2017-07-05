describe ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4 do
  require 'yaml'
  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename.to_s + '.yml'))
  end

  describe "#collect_vms" do
    let(:ems) { FactoryGirl.create(:ems_redhat_with_authentication) }
    let(:vm) { FactoryGirl.create(:vm_redhat, :ext_management_system => ems) }
    let(:ems_service) { instance_double(OvirtSDK4::Connection) }
    let(:system_service) { instance_double(OvirtSDK4::SystemService) }
    let(:vms_service) { instance_double(OvirtSDK4::VmsService) }
    let(:disks_service) { instance_double(OvirtSDK4::DisksService) }
    let(:query) { { :search => "status=#{OvirtSDK4::DataCenterStatus::UP}" } }
    let(:vm1) { load_response_mock_for(:vm1_obj) }
    let(:vm2) { load_response_mock_for(:vm2_obj) }
    let(:vm3) { load_response_mock_for(:vm3_obj) }
    let(:vms_list) { [vm1, vm2, vm3] }
    let(:disks_list) { load_response_mock_for(:disks_list) }

    RSpec::Matchers.define :has_same_href_as do |x|
      match { |actual| x.href == actual.href }
    end

    before do
      allow(ems).to receive(:with_provider_connection).and_yield(ems_service)
      allow(ems_service).to receive(:system_service).and_return(system_service)
      allow(system_service).to receive(:vms_service).and_return(vms_service)
      allow(vms_service).to receive(:list).and_return(vms_list)
      allow(system_service).to receive(:disks_service).and_return(disks_service)
      allow(disks_service).to receive(:list).and_return(disks_list)
      vms_list.each_with_index do |v, i|
        allow(ems_service).to receive(:follow_link).with(has_same_href_as(v.nics)).and_return(load_response_mock_for("vm#{i + 1}_nics"))
        allow(ems_service).to receive(:follow_link).with(has_same_href_as(v.reported_devices)).and_return(load_response_mock_for("vm#{i + 1}_devices"))
        allow(ems_service).to receive(:follow_link).with(has_same_href_as(v.snapshots)).and_return(load_response_mock_for("vm#{i + 1}_snapshots"))
        allow(ems_service).to receive(:follow_link).with(has_same_href_as(v.disk_attachments)).and_return(load_response_mock_for("vm#{i + 1}_attachments"))
      end
    end

    it 'fetches the vms with proper disks' do
      inventory = described_class.new(:ems => ems)
      allow(inventory).to receive(:connection).and_return(ems_service)
      vms = inventory.collect_vms
      expect(vms[0].disks.count).to eq(1)
      expect(vms[1].disks.count).to eq(1)
      expect(vms[2].disks.count).to eq(0)
      expect(vms[0].disks[0].id).to eq("10c3dd0e-90b4-4708-bcba-b71dc4bda979")
      expect(vms[1].disks[0].id).to eq("f067ba7a-563e-4592-8f09-9789cb8cb2c9")
    end
  end
end
