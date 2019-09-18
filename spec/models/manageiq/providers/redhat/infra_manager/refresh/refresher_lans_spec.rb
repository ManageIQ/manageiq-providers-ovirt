require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'pluto-vdsg.eng.lab.tlv.redhat.com', :ipaddress => '10.35.19.13', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_lans_refresh_recording.yml')

    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
  end

  it "lans are not duplicated after refresh" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.name.underscore}_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload
    expect(Lan.count).to eq(7)
    EmsRefresh.refresh(@ems)
    expect(Lan.count).to eq(7)
  end
end
