require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/refresher_network_ports_recording.yml')
  end

  it 'Network port connected to vm guest_device' do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.module_parent.name.underscore}/refresh/refresher_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload

    expect(NetworkPort.count).to eq(1)

    guest_device_uuid = '40c3c841-74be-461f-ac6c-25df73c1b40b'
    rhel_vm = Vm.where(:name => 'vm_on').first
    nic = rhel_vm.nics.where(:uid_ems => guest_device_uuid).first
    connected_port = NetworkPort.where(:device_ref => guest_device_uuid).first

    expect(connected_port.device).to eq(nic)
  end
end
