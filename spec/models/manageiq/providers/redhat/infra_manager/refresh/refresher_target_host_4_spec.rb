require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  let(:ip_address) { '192.168.1.107' }

  before(:each) do
    init_defaults(:hostname => 'pluto-vdsg.eng.lab.tlv.redhat.com', :ipaddress => '10.35.19.13', :port => 443)
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
                                 :ems_ref               => "/ovirt-engine/api/clusters/b875154c-5b87-4068-aa3f-f32c4d672193",
                                 :uid_ems               => "b875154c-5b87-4068-aa3f-f32c4d672193",
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
