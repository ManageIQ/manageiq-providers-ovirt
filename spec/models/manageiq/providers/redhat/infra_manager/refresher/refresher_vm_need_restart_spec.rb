require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'engine-43.lab.inz.redhat.com', :ipaddress => '192.168.178.44', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/refresher_need_restart_recording.yml', :is_recording => true)
  end


  it 'refresh vm' do
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "rhel7s").first
    expect(vm.ems_id).to eq(@ems.id)
    byebug
    saved_vm = vm_to_comparable_hash(vm)
    EmsRefresh.refresh(vm)
    vm.reload
    expect(saved_vm).to eq(vm_to_comparable_hash(vm))
  end
end
