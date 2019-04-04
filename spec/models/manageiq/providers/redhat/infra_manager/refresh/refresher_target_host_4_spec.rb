require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  let(:ip_address) { '192.168.1.107' }

  before(:each) do
    init_defaults(:hostname => 'localhost', :ipaddress => 'localhost', :port => 8443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/refresher_target_host.yml')

    @ems.default_endpoint.path = "/ovirt-engine/api"
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    stub_settings_merge(
      :ems => {
        :ems_redhat => {
          :use_ovirt_engine_sdk => true,
          :resolve_ip_addresses => false
        }
      }
    )
  end

  before(:each) do
    @cluster = FactoryBot.create(:ems_cluster,
                                  :ems_ref               => "/ovirt-engine/api/clusters/59c8cd2d-01d6-0367-037e-0000000002f7",
                                  :uid_ems               => "11acc1a0-66c7-4aba-a00f-fa2648c9b51f",
                                  :ext_management_system => @ems,
                                  :name                  => "Default")

    @host = FactoryBot.create(:host_redhat,
                               :ext_management_system => @ems,
                               :ems_ref               => "/ovirt-engine/api/hosts/11089411-53a2-4337-8613-7c1d411e8ae8",
                               :name                  => "fake_host",
                               :ems_cluster           => @cluster)
  end

  it "should remove a host using graph refresh" do
    EmsRefresh.refresh(@host)
    @ems.reload

    expect(Host.count).to eq(0)
  end
end
