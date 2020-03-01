require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'engine-43.lab.inz.redhat.com', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/refresher_multi_datacenter_network_recording.yml')
  end

  it 'external networks belong to dc' do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.parent.name.underscore}/refresh/refresher_multi_external_network_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload

    expect(ManageIQ::Providers::Redhat::InfraManager::Datacenter.count).to eq(3)
    expect(ManageIQ::Providers::Redhat::InfraManager::DistributedVirtualSwitch.count).to eq(6)
    expect(ManageIQ::Providers::Redhat::InfraManager::ExternalDistributedVirtualSwitch.count).to eq(2)

    dc1 = Datacenter.where(:uid_ems => '5ca0335c-be48-4cf4-acd3-283763cb7e04').first
    dc2 = Datacenter.where(:uid_ems => 'f0bf9fb9-7e8c-4cb2-add7-ab433f30d1fd').first
    dc3 = Datacenter.where(:uid_ems => '2c4d1610-6b88-4330-a745-26e1f2b4ad97').first

    expect(dc1.distributed_virtual_switches.count).to eq(1)
    expect(dc2.distributed_virtual_switches.count).to eq(0)
    expect(dc3.distributed_virtual_switches.count).to eq(1)

    # the following samples works with datacenter_id into switch schema migration
    # expect(dc1.external_distributed_virtual_switches.count).to eq(1)
    # expect(dc1.external_distributed_virtual_lans.count).to eq(1)

    # expect(dc2.external_distributed_virtual_switches.count).to eq(0)
    # expect(dc2.external_distributed_virtual_lans.count).to eq(0)

    # expect(dc3.external_distributed_virtual_switches.count).to eq(1)
    # expect(dc3.external_distributed_virtual_lans.count).to eq(1)
  end
end
