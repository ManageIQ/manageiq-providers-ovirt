require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'engine-43.lab.inz.redhat.com', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/refresher_network_recording.yml')
  end

  it "will perform a full refresh" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.parent.name.underscore}/refresh/refresher_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload

    assert_network

    assert_get_vnic_profiles_in_cluster

    assert_guest_device_connected_to_vm
  end

  def assert_network
    expect(Lan.count).to eq(4)
    expect(ManageIQ::Providers::Redhat::InfraManager::DistributedVirtualSwitch.count).to eq(1)
    expect(ManageIQ::Providers::Redhat::InfraManager::ExternalDistributedVirtualSwitch.count).to eq(1)
    lans = Lan.where(:uid_ems => "265ac89f-98c2-41be-a78b-97852159adb1")
    expect(lans.count).to eq(1)
    lan = lans.first
    expect(lan.name).to eq("vnic1")
    expect(lan.switch.uid_ems).to eq("dac27d35-5858-4663-abd2-bf087050b3eb")
    host = Host.find_by(:uid_ems => "72877001-6012-4921-bdd2-3ff17043083e")
    switch = ManageIQ::Providers::Redhat::InfraManager::DistributedVirtualSwitch.find_by(:uid_ems => "dac27d35-5858-4663-abd2-bf087050b3eb")
    expect(HostSwitch.count).to eq(2)
    expect(HostSwitch.where(:host_id => host.id, :switch_id => switch.id).count).to eq(1)
  end

  def assert_guest_device_connected_to_vm
    vm1 = Vm.find_by(:uid_ems => "ca7e8d64-0fc7-45de-b258-ae471ea31056")
    guest_devices = vm1.hardware.guest_devices
    expect(guest_devices.count).to eq(3)

    nic_ext = vm1.hardware.guest_devices.where(device_name: 'nic_ext').first
    expect(nic_ext.switch.uid_ems).to eq("6a0cb90c-16ac-47ae-b262-ac382b2c42e5")
    expect(nic_ext.lan.uid_ems).to eq("76ec486d-d881-4ad7-ab59-6371cdfcd723")
  end

  def assert_get_vnic_profiles_in_cluster
    ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4.new(:ems => @ems)
    template_uid_ems = "8e418698-62e0-4260-a111-11109aa80c59"
    template_id = VmOrTemplate.find_by(:uid_ems => template_uid_ems).id
    workflow = double(:get_source_vm => double(:id => template_id))
    vlans = {}
    ovirt_service.load_allowed_networks([], vlans, workflow)
    expected_vlans = {"f6898bd4-bcca-4ea4-bedf-3dc976396b36"=>"ovirtmgmt (ovirtmgmt)", "c8df273f-b67c-4527-9423-46b9e4625aed"=>"oVirtB (ovirtmgmt)", 
                      "265ac89f-98c2-41be-a78b-97852159adb1"=>"vnic1 (ovirtmgmt)", "76ec486d-d881-4ad7-ab59-6371cdfcd723"=>"extNetwork (extNetwork)", 
                      "<Empty>"=>"<No Profile>", "<Template>"=>"<Use template nics>"}
    expect(vlans).to eq(expected_vlans)
  end
end
