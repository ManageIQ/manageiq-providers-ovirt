require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/ovirt_lans_refresh_recording.yml')
  end

  it "lans are not duplicated after refresh" do
    EmsRefresh.refresh(@ems)

    VCR.use_cassette("#{described_class.module_parent.name.underscore}/refresh/refresher_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload
    expect(Lan.count).to eq(7)
    EmsRefresh.refresh(@ems)
    expect(Lan.count).to eq(7)
  end
end
