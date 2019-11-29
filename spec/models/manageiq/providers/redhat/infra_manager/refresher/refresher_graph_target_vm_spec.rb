require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_graph_target_vm_deleted_snapshot.yml')

    @ovirt_service_inventory = ManageIQ::Providers::Redhat::InfraManager::Inventory
    allow_any_instance_of(@ovirt_service_inventory)
                     .to receive(:collect_vnic_profiles).and_return([])
    @collector = ManageIQ::Providers::Redhat::Inventory::Collector
    allow_any_instance_of(@collector)
                     .to receive(:collect_vnic_profiles).and_return([])
  end

  COUNTED_MODELS = [CustomAttribute, EmsFolder, EmsCluster, Datacenter].freeze

  it 'does not change the vm when target refresh after full refresh' do
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts,
                                                 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_graph_target_vm_after_full.yml',
                                                 false)
    end
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "vm_on").first
    expect(vm.ems_id).to eq(@ems.id)
    saved_vm             = vm_to_comparable_hash(vm)
    saved_counted_models = COUNTED_MODELS.map { |m| [m.name, m.count] }
    EmsRefresh.refresh(vm)
    vm.reload
    counted_models = COUNTED_MODELS.map { |m| [m.name, m.count] }
    expect(saved_vm).to eq(vm_to_comparable_hash(vm))
    expect(saved_counted_models).to eq(counted_models)
  end

  it 'refreshes vm hosts properly' do
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts,
                                                 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_graph_target_vm_with_host.yml',
                                                 false)
    end
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "vm_on").first
    expect(vm.ems_id).to eq(@ems.id)
    expect(vm.host_id).to be_present
    saved_vm             = vm_to_comparable_hash(vm)
    saved_counted_models = COUNTED_MODELS.map { |m| [m.name, m.count] }
    vm.host              = nil
    vm.save
    EmsRefresh.refresh(vm)
    vm.reload
    counted_models = COUNTED_MODELS.map { |m| [m.name, m.count] }
    expect(saved_vm).to eq(vm_to_comparable_hash(vm))
    expect(saved_counted_models).to eq(counted_models)
  end

  it 'refreshes successfuly after snapshot removal' do
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "vm_on_with_snapshots").first
    expect(vm.reload.snapshots.count).to eq(2)
    EmsRefresh.refresh(vm)
    expect(vm.reload.snapshots.count).to eq(1)
  end

  it 'refreshes successfuly after vm removal' do
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts,
                                                 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_graph_target_vm_removal.yml',
                                                 false)
    end
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.where(:name => "vm_to_be_deleted").first
    expect(VmOrTemplate.where(:name => "vm_to_be_deleted").first.ems_id).not_to be_nil
    EmsRefresh.refresh(vm)
    expect(VmOrTemplate.where(:name => "vm_to_be_deleted").first.ems_id).to be_nil
  end

  def vm_to_comparable_hash(vm)
    h = vm.attributes
    h.delete("updated_on")
    h.delete("state_changed_on")
    h
  end
end
