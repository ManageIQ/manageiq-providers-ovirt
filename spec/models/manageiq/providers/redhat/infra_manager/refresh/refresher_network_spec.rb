require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'pluto-vdsg.eng.lab.tlv.redhat.com', :port => 443, :external_network_provider_mock => 'external_network_providers_new')
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/refresher_network_recording.yml')

    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
  end

  it "will perform a full refresh on v4.1" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.parent.name.underscore}/refresher_ovn_provider_1") do
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
    lans = Lan.where(:uid_ems => "57fe1346-b203-4050-bf90-a9569a40024e")
    expect(lans.count).to eq(1)
    lan = lans.first
    expect(lan.name).to eq("vnic1")
    expect(lan.switch.uid_ems).to eq("00000000-0000-0000-0000-000000000009")
    host = Host.find_by(:uid_ems => "9a0e0300-cd5e-495a-8cf8-67244de80a33")
    switch = ManageIQ::Providers::Redhat::InfraManager::DistributedVirtualSwitch.find_by(:uid_ems => "00000000-0000-0000-0000-000000000009")
    expect(HostSwitch.count).to eq(2)
    expect(HostSwitch.where(:host_id => host.id, :switch_id => switch.id).count).to eq(1)
  end

  def assert_guest_device_connected_to_vm
    vm1 = Vm.find_by(:uid_ems => "2c4eb887-e642-4016-af1e-640cdeeb209b")
    guest_devices = vm1.hardware.guest_devices
    expect(guest_devices.count).to eq(1)
    expect(guest_devices.first.switch.uid_ems).to eq("a7ef5b9e-46cd-4046-9615-51c7427598d4")
    expect(guest_devices.first.lan.uid_ems).to eq("83b845f7-9c8b-4ff1-a111-37aadd5950e4")
  end

  def assert_get_vnic_profiles_in_cluster
    ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4.new(:ems => @ems)
    template_uid_ems = "0e6bd5ff-be07-42b2-bb7b-f268b09d3ef0"
    template_id = VmOrTemplate.find_by(:uid_ems => template_uid_ems).id
    workflow = double(:get_source_vm => double(:id => template_id))
    vlans = {}
    ovirt_service.load_allowed_networks([], vlans, workflow)
    expected_vlans = {"0000000a-000a-000a-000a-000000000398" => "ovirtmgmt (ovirtmgmt)", "83b845f7-9c8b-4ff1-a111-37aadd5950e4" => "extnetwork (extnetwork)",
                      "57fe1346-b203-4050-bf90-a9569a40024e" => "vnic1 (ovirtmgmt)", "c103e9a6-4a94-4929-a86b-d9e0520dbebe" => "vnic_ext (extnetwork)",
                      "<Empty>" => "<No Profile>", "<Template>" => "<Use template nics>"}
    expect(vlans).to eq(expected_vlans)
  end
end
