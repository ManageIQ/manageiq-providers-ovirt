require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'engine-43.lab.inz.redhat.com', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/refresher_network_ports_recording.yml')
  end

  it 'Network port connected to vm guest_device' do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.module_parent.name.underscore}/refresh/refresher_network_ports_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload

    expect(NetworkPort.count).to eq(4)

    guest_device_uuid = '6afaa917-1f0b-4967-8ecf-f45cfbd5d0ba'
    rhel_vm = Vm.where(:name => 'rhel_seven').first
    nic = rhel_vm.nics.where(:uid_ems => guest_device_uuid).first
    connected_port = NetworkPort.where(:device_ref => guest_device_uuid).first

    expect(connected_port.device).to eq(nic)
  end
end
