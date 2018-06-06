require 'fog/openstack'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  before(:each) do
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryGirl.create(:ems_redhat, :zone => zone, :hostname => "pluto-vdsg.eng.lab.tlv.redhat.com", :ipaddress => "10.35.19.13",
                              :port => 443)
    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "123456"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
    allow(@ems).to(receive(:supported_api_versions).and_return(%w(3 4)))
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts, 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording_custom_attrs.yml', false)
    end
    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  before(:each) do
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4

    allow_any_instance_of(@inventory_wrapper_class).to(receive(:api).and_return("4.2.0_master."))
    allow_any_instance_of(@inventory_wrapper_class).to(receive(:service)
      .and_return(OpenStruct.new(:version_string => '4.2.0_master.')))
  end

  require 'yaml'
  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
  end

  it "will fetch custom_attributes for full and targeted refresh" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.name.underscore}_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload
    vm = Vm.where(:name => 'my-cirros-vm').first
    expect(vm.custom_attributes.count).to eq(1)
    EmsRefresh.refresh(vm)
    vm.reload
    expect(vm.custom_attributes.count).to eq(1)
  end
end
