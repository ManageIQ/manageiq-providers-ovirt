describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  let(:ip_address) { '192.168.1.107' }

  before(:each) do
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryGirl.create(:ems_redhat, :zone => zone, :hostname => "localhost", :ipaddress => "localhost",
                              :port => 8443)
    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
    allow_any_instance_of(@ovirt_service)
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "engine"})
    @ems.default_endpoint.path = "/ovirt-engine/api"
    allow(@ems).to receive(:supported_api_versions).and_return(%w(3 4))
    stub_settings_merge(
      :ems => {
        :ems_redhat => {
          :use_ovirt_engine_sdk => true,
          :resolve_ip_addresses => false
        }
      }
    )
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts, 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/refresher_target_host.yml')
    end
    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  before(:each) do
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4

    allow_any_instance_of(@inventory_wrapper_class).to(receive(:api).and_return("4.2.0_master."))
    allow_any_instance_of(@inventory_wrapper_class).to(receive(:service)
      .and_return(OpenStruct.new(:version_string => '4.2.0_master.')))

    @cluster = FactoryGirl.create(:ems_cluster,
                                  :ems_ref               => "/ovirt-engine/api/clusters/59c8cd2d-01d6-0367-037e-0000000002f7",
                                  :uid_ems               => "11acc1a0-66c7-4aba-a00f-fa2648c9b51f",
                                  :ext_management_system => @ems,
                                  :name                  => "Default")

    @host = FactoryGirl.create(:host_redhat,
                               :ext_management_system => @ems,
                               :ems_ref               => "/ovirt-engine/api/hosts/11089411-53a2-4337-8613-7c1d411e8ae8",
                               :name                  => "fake_host",
                               :ems_cluster           => @cluster)
  end

  require 'yaml'
  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
  end

  it "should remove a host using graph refresh" do
    EmsRefresh.refresh(@host)
    @ems.reload

    expect(Host.count).to eq(0)
  end
end
