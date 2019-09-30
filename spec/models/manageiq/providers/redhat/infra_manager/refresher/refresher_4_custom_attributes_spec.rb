require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording_custom_attrs.yml')

    @collector = ManageIQ::Providers::Redhat::Inventory::Collector

    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
  end

  CASSETTE_PATH = "#{described_class.parent.name.underscore}/refresh/refresher_ovn_provider".freeze

  it "will fetch custom_attributes for full and targeted refresh" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette(CASSETTE_PATH) do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload
    vm = Vm.where(:name => 'vm_off').first
    expect(vm.custom_attributes.count).to eq(1)
    EmsRefresh.refresh(vm)
    vm.reload
    expect(vm.custom_attributes.count).to eq(1)
  end

  it "does not clear miq_custom_attributes for full and targeted refresh" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette(CASSETTE_PATH) do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end

    vm = Vm.where(:name => 'vm_off').first
    vm.ems_custom_attributes.first.destroy # This should be recreated
    vm.ems_custom_attributes.create(:section => 'custom_field', :name => "delete_me", :value => "please") # This should be deleted
    vm.miq_custom_set('test-key', 'test-val')

    @ems.reload
    vm.reload
    expect(vm.miq_custom_attributes.count).to eq(1)
    expect(vm.ems_custom_attributes.count).to eq(1)
    expect(vm.ems_custom_attributes.first.name).to eq("delete_me")
    EmsRefresh.refresh(vm)
    vm.reload
    expect(vm.miq_custom_attributes.count).to eq(1)
    expect(vm.ems_custom_attributes.count).to eq(1)
    expect(vm.ems_custom_attributes.first.name).not_to eq("delete_me")
  end

  it "does not clear ems_custom_attributes for other vms" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette(CASSETTE_PATH) do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end

    vm = Vm.find_by(:name => 'vm_on')
    other_vm = Vm.find_by(:name => 'vm_off')

    expect(other_vm.ems_custom_attributes.count).to eq(1)

    @ems.reload
    EmsRefresh.refresh(vm)

    expect(other_vm.reload.ems_custom_attributes.count).to eq(1)
  end
end
