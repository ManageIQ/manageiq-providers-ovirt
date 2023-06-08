require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    secrets = Rails.application.secrets.ovirt
    init_defaults(:hostname => secrets[:hostname], :ipaddress => secrets[:ipaddress])
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/refresher_reconfigure_with_restart_needed_recording.yml')
  end

  it 'cores per socket decrease needs a restart' do
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "rhel7s").first

    expect(vm.restart_needed).to be_falsey
    expect(vm.hardware.cpu_cores_per_socket).to eq(2)

    @ems.vm_reconfigure(vm, :spec => { 'numCPUs' => 2, 'numCoresPerSocket' => 1 })

    EmsRefresh.refresh(vm)
    vm.reload

    expect(vm.restart_needed).to be_truthy
  end

  it 'cores increase does not need a restart' do
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts,
                                                 'spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/refresher_reconfigure_with_no_restart_needed_recording.yml',
                                                 false)
    end
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "rhel7s").first

    expect(vm.restart_needed).to be_falsey
    expect(vm.hardware.cpu_cores_per_socket).to eq(1)
    expect(vm.hardware.cpu_sockets).to eq(2)

    @ems.vm_reconfigure(vm, :spec => { 'numCPUs' => 4, 'numCoresPerSocket' => 1 })

    EmsRefresh.refresh(vm)
    vm.reload

    expect(vm.restart_needed).to be_falsey
    expect(vm.hardware.cpu_sockets).to eq(4)
  end
end
