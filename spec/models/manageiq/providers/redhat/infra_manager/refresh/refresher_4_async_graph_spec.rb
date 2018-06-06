require 'fog/openstack'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  before(:each) do
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryGirl.create(:ems_redhat, :zone => zone, :hostname => "localhost", :ipaddress => "localhost",
                              :port => 8443)
    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "123456"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
    allow(@ems).to(receive(:supported_api_versions).and_return(%w(3 4)))
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts, 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording.yml')
    end
    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  before(:each) do
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4

    allow_any_instance_of(@inventory_wrapper_class).to(receive(:api).and_return("4.2.0_master."))
    allow_any_instance_of(@inventory_wrapper_class).to(receive(:service)
      .and_return(OpenStruct.new(:version_string => '4.2.0_master.')))
  end

  require 'yaml'
  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
  end

  it "will perform a full refresh on v4.1" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.name.underscore}_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload

    assert_table_counts(3)
    assert_ems
    assert_network_manager
    assert_specific_cluster
    assert_specific_storage
    assert_specific_host
    assert_specific_vm_powered_on
    assert_specific_vm_powered_off
    assert_specific_template
    assert_relationship_tree
  end

  it "will perform a refresh and reconnect a host" do
    FactoryGirl.create(:host_redhat,
                       :ext_management_system => nil,
                       :ems_ref               => "/api/hosts/5bf6b336-f86d-4551-ac08-d34621ec5f0a",
                       :ems_ref_obj           => "/api/hosts/5bf6b336-f86d-4551-ac08-d34621ec5f0a",
                       :name                  => "bodh1",
                       :hostname              => "bodh1.usersys.redhat.com",
                       :ipaddress             => "10.35.19.12",
                       :uid_ems               => "5bf6b336-f86d-4551-ac08-d34621ec5f0a")

    EmsRefresh.refresh(@ems)
    @ems.reload

    host = Host.find_by(:name => "bodh1")
    expect(host.ext_management_system).to eq(@ems)
    expect(Host.where(:uid_ems => "5bf6b336-f86d-4551-ac08-d34621ec5f0a").count).to eq 1
  end

  it "will perform a refresh and reconnect a vm" do
    @vm = FactoryGirl.create(:vm_redhat,
                             :ext_management_system => nil,
                             :ems_ref               => "/api/vms/3a9401a0-bf3d-4496-8acf-edd3e903511f",
                             :ems_ref_obj           => "/api/vms/3a9401a0-bf3d-4496-8acf-edd3e903511f",
                             :uid_ems               => "3a9401a0-bf3d-4496-8acf-edd3e903511f",
                             :vendor                => "redhat",
                             :raw_power_state       => "up",
                             :location              => "3a9401a0-bf3d-4496-8acf-edd3e903511f.ovf")

    EmsRefresh.refresh(@ems)
    @ems.reload

    vm = VmOrTemplate.find_by(:uid_ems => "3a9401a0-bf3d-4496-8acf-edd3e903511f")
    expect(vm.ext_management_system).to eq(@ems)
    expect(VmOrTemplate.where(:uid_ems => "3a9401a0-bf3d-4496-8acf-edd3e903511f").count).to eq 1
  end

  def assert_table_counts(_lan_number)
    expect(ExtManagementSystem.count).to eq(2)
    expect(EmsFolder.count).to eq(7)
    expect(EmsCluster.count).to eq(3)
    expect(Host.count).to eq(3)
    expect(ResourcePool.count).to eq(3)
    expect(VmOrTemplate.count).to eq(17)
    expect(Vm.count).to eq(14)
    expect(MiqTemplate.count).to eq(3)
    expect(Storage.count).to eq(5)

    expect(CustomAttribute.count).to eq(0) # TODO: 3.0 spec has values for this
    expect(CustomizationSpec.count).to eq(0)
    expect(Disk.count).to eq(15)
    expect(GuestDevice.count).to eq(18)
    expect(Hardware.count).to eq(20)
    expect(Lan.count).to eq(2)
    expect(MiqScsiLun.count).to eq(0)
    expect(MiqScsiTarget.count).to eq(0)
    expect(Network.count).to eq(6)
    expect(OperatingSystem.count).to eq(20)
    expect(Snapshot.count).to eq(17)
    # the old code expects 3 and new 2
    expect(Switch.count).to eq(2)
    expect(SystemService.count).to eq(0)

    expect(Relationship.count).to eq(45)
    expect(MiqQueue.count).to eq(21)

    expect(CloudNetwork.count).to eq(6)
    expect(CloudSubnet.count).to eq(2)
    expect(NetworkRouter.count).to eq(1)
    expect(NetworkPort.count).to eq(1)
  end

  def assert_ems
    expect(@ems).to have_attributes(
      :api_version => "4.2.0_master.",
      :uid_ems     => nil
    )

    expect(@ems.ems_folders.size).to eq(7)
    expect(@ems.ems_clusters.size).to eq(3)
    expect(@ems.resource_pools.size).to eq(3)
    expect(@ems.storages.size).to eq(4)
    expect(@ems.hosts.size).to eq(3)
    expect(@ems.vms_and_templates.size).to eq(17)
    expect(@ems.vms.size).to eq(14)
    expect(@ems.miq_templates.size).to eq(3)

    expect(@ems.customization_specs.size).to eq(0)
  end

  def assert_network_manager
    @network_manager = ExtManagementSystem.find_by(:type => 'ManageIQ::Providers::Redhat::NetworkManager')
    expect(@network_manager).to have_attributes(
      :name              => @ems.name + " Network Manager",
      :hostname          => "localhost",
      :port              => 35_357,
      :api_version       => "v2",
      :security_protocol => "non-ssl",
      :zone_id           => @ems.zone_id
    )

    assert_specific_cloud_network
    assert_specific_network_router
    assert_specific_network_port
  end

  def assert_specific_cloud_network
    @cloud_network = CloudNetwork.find_by(:name => "net1")
    expect(@cloud_network).to have_attributes(
      :ems_id                    => @ems.network_manager.id,
      :type                      => "ManageIQ::Providers::Openstack::NetworkManager::CloudNetwork::Private",
      :name                      => "net1",
      :ems_ref                   => "3bd87e3d-f66a-4e9c-ab56-62f98db791db",
      :shared                    => nil,
      :status                    => "active",
      :enabled                   => nil,
      :external_facing           => nil,
      :orchestration_stack       => nil,
      :provider_physical_network => nil,
      :provider_network_type     => nil,
      :provider_segmentation_id  => nil,
      :port_security_enabled     => nil,
      :qos_policy_id             => nil,
      :vlan_transparent          => nil,
      :maximum_transmission_unit => nil
    )

    @cloud_tenant = @cloud_network.cloud_tenant

    expect(@cloud_tenant).to have_attributes(
      :ems_id      => @ems.id,
      :type        => "ManageIQ::Providers::Openstack::CloudManager::CloudTenant",
      :name        => "tenant",
      :description => "tenant",
      :enabled     => true,
      :ems_ref     => "00000000000000000000000000000001",
      :parent_id   => nil,
    )

    expect(@cloud_network.cloud_subnets.count).to eq(1)
    @cloud_subnet = @cloud_network.cloud_subnets.first
    expect(@cloud_subnet).to have_attributes(
      :ems_id                         => @ems.network_manager.id,
      :type                           => "ManageIQ::Providers::Openstack::NetworkManager::CloudSubnet",
      :name                           => "sub_net1",
      :ems_ref                        => "5bcefbad-cde7-4410-943d-0b5c168c1c3c",
      :cidr                           => "11.0.0.0/24",
      :status                         => "active",
      :network_protocol               => "ipv4",
      :gateway                        => "11.0.0.0",
      :dhcp_enabled                   => true,
      :dns_nameservers                => [],
      :ipv6_router_advertisement_mode => nil,
      :ipv6_address_mode              => nil,
      :allocation_pools               => [{"start" => "11.0.0.2", "stop" => "11.0.0.255"}],
      :host_routes                    => nil,
      :ip_version                     => 4,
      :cloud_tenant_id                => @cloud_tenant.id,
      :parent_cloud_subnet            => nil
    )

    # TODO: test a port connected to a subnet, currently there is a bug in the provider avoids testing it
  end

  def assert_specific_network_router
    @router = NetworkRouter.find_by(:name => "router1")
    expect(@router).to have_attributes(
      :ems_id                => @ems.network_manager.id,
      :type                  => "ManageIQ::Providers::Openstack::NetworkManager::NetworkRouter",
      :name                  => "router1",
      :ems_ref               => "1a12e744-ee50-4fee-a8d5-f6636e27470d",
      :admin_state_up        => "t",
      :status                => "ACTIVE",
      :external_gateway_info => nil,
      :distributed           => nil,
      :routes                => [],
      :high_availability     => nil,
      :cloud_tenant_id       => @cloud_tenant.id,
      :cloud_network         => nil
    )
  end

  def assert_specific_network_port
    @port = NetworkPort.find_by(:name => "nic2")
    expect(@port).to have_attributes(
      :ems_id                            => @ems.network_manager.id,
      :type                              => "ManageIQ::Providers::Openstack::NetworkManager::NetworkPort",
      :name                              => "nic2",
      :ems_ref                           => "2ca0b52d-9af5-4968-82e8-226cec6e6db7",
      :admin_state_up                    => false,
      :status                            => nil,
      :mac_address                       => "00:1a:4a:16:01:01",
      :device_owner                      => "oVirt",
      :device_ref                        => "d1a9b8ed-6d6c-4299-a9bb-a5277ce5b513",
      :device                            => nil,
      :cloud_tenant_id                   => @cloud_tenant.id,
      :binding_host_id                   => nil,
      :binding_virtual_interface_type    => nil,
      :binding_virtual_interface_details => nil,
      :binding_profile                   => nil,
      :extra_dhcp_opts                   => nil,
      :allowed_address_pairs             => nil
    )
  end

  def assert_specific_cluster
    @cluster = EmsCluster.find_by(:name => 'cc1')
    expect(@cluster).to have_attributes(
      :ems_ref                 => "/api/clusters/504ae500-3476-450e-8243-f6df0f7f7acf",
      :ems_ref_obj             => "/api/clusters/504ae500-3476-450e-8243-f6df0f7f7acf",
      :uid_ems                 => "504ae500-3476-450e-8243-f6df0f7f7acf",
      :name                    => "cc1",
      :ha_enabled              => nil, # TODO: Should be true
      :ha_admit_control        => nil,
      :ha_max_failures         => nil,
      :drs_enabled             => nil, # TODO: Should be true
      :drs_automation_level    => nil,
      :drs_migration_threshold => nil
    )

    expect(@cluster.all_resource_pools_with_default.size).to eq(1)
    @default_rp = @cluster.default_resource_pool

    expect(@default_rp).to have_attributes(
      :ems_ref               => nil,
      :ems_ref_obj           => nil,
      :uid_ems               => "504ae500-3476-450e-8243-f6df0f7f7acf_respool",
      :name                  => "Default for Cluster cc1",
      :memory_reserve        => nil,
      :memory_reserve_expand => nil,
      :memory_limit          => nil,
      :memory_shares         => nil,
      :memory_shares_level   => nil,
      :cpu_reserve           => nil,
      :cpu_reserve_expand    => nil,
      :cpu_limit             => nil,
      :cpu_shares            => nil,
      :cpu_shares_level      => nil,
      :is_default            => true
    )
  end

  def assert_specific_storage
    @storage = Storage.find_by(:name => "data1")
    expect(@storage).to have_attributes(
      :ems_ref                       => "/api/storagedomains/27a3bcce-c4d0-4bce-afe9-1d669d5a9d02",
      :ems_ref_obj                   => "/api/storagedomains/27a3bcce-c4d0-4bce-afe9-1d669d5a9d02",
      :name                          => "data1",
      :store_type                    => "NFS",
      :total_space                   => 53_687_091_200,
      :free_space                    => 46_170_898_432,
      :uncommitted                   => -97_710_505_984,
      :multiplehostaccess            => 1, # TODO: Should this be a boolean column?
      :location                      => "spider.eng.lab.tlv.redhat.com:/vol/vol_bodnopoz/data1",
      :directory_hierarchy_supported => nil,
      :thin_provisioning_supported   => nil,
      :raw_disk_mappings_supported   => nil
    )

    @storage2 = Storage.find_by(:name => "data2")
    expect(@storage2).to have_attributes(
      :ems_ref                       => "/api/storagedomains/4672fe17-c260-4ecc-aab0-b535f4d0dbeb",
      :ems_ref_obj                   => "/api/storagedomains/4672fe17-c260-4ecc-aab0-b535f4d0dbeb",
      :name                          => "data2",
      :store_type                    => "NFS",
      :total_space                   => 53_687_091_200,
      :free_space                    => 46_170_898_432,
      :uncommitted                   => 53_687_091_200,
      :multiplehostaccess            => 1, # TODO: Should this be a boolean column?
      :location                      => "spider.eng.lab.tlv.redhat.com:/vol/vol_bodnopoz/data2",
      :directory_hierarchy_supported => nil,
      :thin_provisioning_supported   => nil,
      :raw_disk_mappings_supported   => nil
    )

    def assert_specific_host
      @host = ManageIQ::Providers::Redhat::InfraManager::Host.find_by(:name => "bodh1")
      expect(@host).to have_attributes(
        :ems_ref          => "/api/hosts/5bf6b336-f86d-4551-ac08-d34621ec5f0a",
        :ems_ref_obj      => "/api/hosts/5bf6b336-f86d-4551-ac08-d34621ec5f0a",
        :name             => "bodh1",
        :hostname         => "bodh1.usersys.redhat.com",
        :ipaddress        => "10.35.19.12",
        :uid_ems          => "5bf6b336-f86d-4551-ac08-d34621ec5f0a",
        :vmm_vendor       => "redhat",
        :vmm_version      => "7",
        :vmm_product      => "rhel",
        :vmm_buildnumber  => nil,
        :power_state      => "on",
        :maintenance      => false,
        :connection_state => "connected"
      )

      @host_cluster = EmsCluster.find_by(:ems_ref => "/api/clusters/00000002-0002-0002-0002-000000000092")
      expect(@host.ems_cluster).to eq(@host_cluster)
      expect(@host.storages.size).to eq(1)
      expect(@host.storages).to include(@storage2) ### MIGHT BE WRONG, CHECK MANUALLY

      expect(@host.operating_system).to have_attributes(
        :name         => "bodh1.usersys.redhat.com",
        :product_name => "RHEL",
        :version      => "7 - 1.1503.el7.centos.2.8",
        :build_number => nil,
        :product_type => "linux"
      )

      expect(@host.system_services.size).to eq(0)

      expect(@host.switches.size).to eq(1)

      switch = @host.switches.first
      expect(switch).to have_attributes(
        :uid_ems           => "00000000-0000-0000-0000-000000000009",
        :name              => "ovirtmgmt",
        :ports             => nil,
        :allow_promiscuous => nil,
        :forged_transmits  => nil,
        :mac_changes       => nil
      )

      expect(switch.lans.size).to eq(1)

      @lan = switch.lans.first
      expect(@lan).to have_attributes(
        :uid_ems                    => "00000000-0000-0000-0000-000000000009",
        :name                       => "ovirtmgmt",
        :tag                        => nil,
        :allow_promiscuous          => nil,
        :forged_transmits           => nil,
        :mac_changes                => nil,
        :computed_allow_promiscuous => nil,
        :computed_forged_transmits  => nil,
        :computed_mac_changes       => nil
      )

      expect(@host.hardware).to have_attributes(
        :cpu_speed            => 2400,
        :cpu_type             => "Westmere E56xx/L56xx/X56xx (Nehalem-C)",
        :manufacturer         => "Red Hat",
        :model                => "RHEV Hypervisor",
        :number_of_nics       => 1,
        :memory_mb            => 3789,
        :memory_console       => nil,
        :cpu_sockets          => 2,
        :cpu_total_cores      => 2,
        :cpu_cores_per_socket => 1,
        :guest_os             => nil,
        :guest_os_full_name   => nil,
        :vmotion_enabled      => nil,
        :cpu_usage            => nil,
        :memory_usage         => nil,
        :serial_number        => "30353036-3837-4247-3831-303946353239"
      )

      expect(@host.hardware.networks.size).to eq(1)

      network = @host.hardware.networks.find_by(:description => "eth0")
      expect(network).to have_attributes(
        :description  => "eth0",
        :dhcp_enabled => nil,
        :ipaddress    => "10.35.19.12",
        :subnet_mask  => "255.255.252.0"
      )

      # TODO: Verify this host should have 3 nics, 2 cdroms, 1 floppy, any storage adapters?
      expect(@host.hardware.guest_devices.size).to eq(1)

      expect(@host.hardware.nics.size).to eq(1)
      nic = @host.hardware.nics.first

      expect(nic).to have_attributes(
        :uid_ems         => "01c2d4a8-5d7a-4960-bfc4-ca1b400a9bdd",
        :device_name     => "eth0",
        :device_type     => "ethernet",
        :location        => "0",
        :present         => true,
        :controller_type => "ethernet"
      )
      expect(nic.switch).to eq(switch)
      expect(nic.network).to eq(network)

      expect(@host.hardware.storage_adapters.size).to eq(0) # TODO: See @host.hardware.guest_devices TODO
    end

    def assert_specific_vm_powered_on
      v = ManageIQ::Providers::Redhat::InfraManager::Vm.find_by(:name => "vm1")
      expect(v).to have_attributes(
        :template              => false,
        :ems_ref               => "/api/vms/3a9401a0-bf3d-4496-8acf-edd3e903511f",
        :ems_ref_obj           => "/api/vms/3a9401a0-bf3d-4496-8acf-edd3e903511f",
        :uid_ems               => "3a9401a0-bf3d-4496-8acf-edd3e903511f",
        :vendor                => "redhat",
        :raw_power_state       => "up",
        :power_state           => "on",
        :location              => "3a9401a0-bf3d-4496-8acf-edd3e903511f.ovf",
        :tools_status          => nil,
        :boot_time             => Time.zone.parse("2017-08-02T06:53:36.148"),
        :standby_action        => nil,
        :connection_state      => "connected",
        :cpu_affinity          => nil,
        :memory_reserve        => 2024,
        :memory_reserve_expand => nil,
        :memory_limit          => 8096,
        :memory_shares         => nil,
        :memory_shares_level   => nil,
        :cpu_reserve           => nil,
        :cpu_reserve_expand    => nil,
        :cpu_limit             => nil,
        :cpu_shares            => nil,
        :cpu_shares_level      => nil
      )

      expect(v.ext_management_system).to eq(@ems)
      expect(v.ems_cluster).to eq(@cluster)
      expect(v.parent_resource_pool).to eq(@default_rp)

      host = ManageIQ::Providers::Redhat::InfraManager::Host.find_by(:name => "bodh2")
      expect(v.host).to eq(host)
      expect(v.storages).to eq([@storage])

      expect(v.operating_system).to have_attributes(
        :product_name => "other"
      )

      expect(v.hostnames).to match_array(["vm-18-82.eng.lab.tlv.redhat.com"])
      expect(v.custom_attributes.size).to eq(0)

      expect(v.snapshots.size).to eq(3)

      # TODO: Fix this boolean column
      snapshot = v.snapshots.detect { |s| s.name = "Active VM" } # TODO: Fix this boolean column
      expect(snapshot).to have_attributes(
        :uid         => "6e3e547f-9544-42cf-842d-9104828d8511",
        :parent_uid  => "05ff445a-0bfc-44c3-90d1-a338e9095510",
        :uid_ems     => "6e3e547f-9544-42cf-842d-9104828d8511",
        :name        => "Active VM",
        :description => "Active VM",
        :current     => 0,
        :total_size  => nil,
        :filename    => nil
      )
      snapshot_parent = ::Snapshot.find_by(:name => "vm1_snap")
      expect(snapshot.parent).to eq(snapshot_parent)
      expect(snapshot_parent.current).to eq(1)

      expect(v.hardware).to have_attributes(
        :guest_os             => "other",
        :guest_os_full_name   => nil,
        :bios                 => nil,
        :cpu_cores_per_socket => 1,
        :cpu_total_cores      => 4,
        :cpu_sockets          => 4,
        :annotation           => nil,
        :memory_mb            => 2024
      )

      expect(v.hardware.disks.size).to eq(1)

      disk = v.hardware.disks.find_by(:device_name => "vm1_Disk1")
      expect(disk).to have_attributes(
        :device_name     => "vm1_Disk1",
        :device_type     => "disk",
        :controller_type => "virtio",
        :present         => true,
        :filename        => "af578e0e-b222-4754-aefc-879bf37eacec",
        :location        => "0",
        :size            => 6_442_450_944,
        :size_on_disk    => 93_106_176,
        :mode            => "persistent",
        :disk_type       => "thin",
        :start_connected => true
      )
      expect(disk.storage).to eq(@storage) ## CHECK MANUALLY

      expect(v.hardware.guest_devices.size).to eq(1)
      expect(v.hardware.nics.size).to eq(1)

      nic = v.hardware.nics.find_by(:device_name => "nic1")
      expect(nic).to have_attributes(
        :uid_ems         => "6a538d86-38a2-4ac9-98f5-9d401a596e93",
        :device_name     => "nic1",
        :device_type     => "ethernet",
        :controller_type => "ethernet",
        :present         => true,
        :start_connected => true,
        :address         => "00:1a:4a:16:01:51"
      )
      # nic.lan.should == @lan # TODO: Hook up this connection

      guest_device = v.hardware.guest_devices.find_by(:device_name => "nic1")
      expect(guest_device.network).not_to be_nil
      expect(guest_device.network).to have_attributes(
        :ipaddress   => "10.35.18.141",
        :ipv6address => "2620:52:0:2310:21a:4aff:fe16:151",
        :hostname    => "vm-18-82.eng.lab.tlv.redhat.com"
      )

      expect(v.hardware.networks.size).to eq(2)
      network = v.hardware.networks.find_by(:ipv6address => "fe80::21a:4aff:fe16:151")
      expect(network).not_to be_nil
      expect(network).to have_attributes(
        :ipaddress => nil,
        :hostname  => "vm-18-82.eng.lab.tlv.redhat.com"
      )

      expect(v.parent_datacenter).to have_attributes(
        :ems_ref     => "/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :ems_ref_obj => "/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :uid_ems     => "b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :name        => "dc1",
        :type        => "Datacenter",
        :folder_path => "Datacenters/dc1"
      )

      expect(v.parent_folder).to have_attributes(
        :ems_ref     => nil,
        :ems_ref_obj => nil,
        :uid_ems     => "root_dc",
        :name        => "Datacenters",
        :type        => nil,
        :folder_path => "Datacenters"
      )

      expect(v.parent_blue_folder).to have_attributes(
        :ems_ref     => nil,
        :ems_ref_obj => nil,
        :uid_ems     => "b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1_vm",
        :name        => "vm",
        :type        => nil,
        :folder_path => "Datacenters/dc1/vm"
      )
    end

    def assert_specific_vm_powered_off
      v = ManageIQ::Providers::Redhat::InfraManager::Vm.find_by(:name => "iso_t2")
      expect(v).to have_attributes(
        :template              => false,
        :ems_ref               => "/api/vms/1010ec66-5d68-4ae6-b72b-824f5885259d",
        :ems_ref_obj           => "/api/vms/1010ec66-5d68-4ae6-b72b-824f5885259d",
        :uid_ems               => "1010ec66-5d68-4ae6-b72b-824f5885259d",
        :vendor                => "redhat",
        :raw_power_state       => "down",
        :power_state           => "off",
        :location              => "1010ec66-5d68-4ae6-b72b-824f5885259d.ovf",
        :tools_status          => nil,
        :boot_time             => nil,
        :standby_action        => nil,
        :connection_state      => "connected",
        :cpu_affinity          => nil,
        :memory_reserve        => 1024,
        :memory_reserve_expand => nil,
        :memory_limit          => 4096,
        :memory_shares         => nil,
        :memory_shares_level   => nil,
        :cpu_reserve           => nil,
        :cpu_reserve_expand    => nil,
        :cpu_limit             => nil,
        :cpu_shares            => nil,
        :cpu_shares_level      => nil
      )

      expect(v.ext_management_system).to eq(@ems)
      expect(v.ems_cluster).to eq(@cluster)
      expect(v.parent_resource_pool).to eq(@default_rp)
      expect(v.storages).to eq([@storage]) # CHECK MANUALLY

      expect(v.operating_system).to have_attributes(
        :product_name => "other"
      )

      expect(v.hostnames).to match_array([])
      expect(v.custom_attributes.size).to eq(0)

      expect(v.snapshots.size).to eq(1)
      # TODO: Fix this boolean column
      snapshot = v.snapshots.detect { |s| s.current == 1 } # TODO: Fix this boolean column
      expect(snapshot).to have_attributes(
        :uid         => "c4b36a70-faf4-45e9-bd7d-e7d6470d1855",
        :parent_uid  => nil,
        :uid_ems     => "c4b36a70-faf4-45e9-bd7d-e7d6470d1855",
        :name        => "Active VM",
        :description => "Active VM",
        :current     => 1,
        :total_size  => nil,
        :filename    => nil
      )
      expect(snapshot.parent).to be_nil

      expect(v.hardware).to have_attributes(
        :guest_os             => "other",
        :guest_os_full_name   => nil,
        :bios                 => nil,
        :cpu_cores_per_socket => 1,
        :cpu_total_cores      => 4,
        :cpu_sockets          => 4,
        :annotation           => "",
        :memory_mb            => 1024
      )

      expect(v.hardware.disks.size).to eq(1)

      disk = v.hardware.disks.find_by(:device_name => "vm1_Disk1")
      expect(disk).to have_attributes(
        :device_name     => "vm1_Disk1",
        :device_type     => "disk",
        :controller_type => "virtio",
        :present         => true,
        :filename        => "e0001bb7-3e18-457d-af89-8e5b565cc84f",
        :location        => "0",
        :size            => 6_442_450_944,
        :size_on_disk    => 0,
        :mode            => "persistent",
        :disk_type       => "thin",
        :start_connected => true
      )
      expect(disk.storage).to eq(@storage) ## CHECK MANUALLY

      expect(v.hardware.guest_devices.size).to eq(1)
      expect(v.hardware.nics.size).to eq(1)

      nic = v.hardware.nics.find_by(:device_name => "nic1")
      expect(nic).to have_attributes(
        :uid_ems         => "cbcf2311-8577-49d4-9670-4e97f9fec853",
        :device_name     => "nic1",
        :device_type     => "ethernet",
        :controller_type => "ethernet",
        :present         => true,
        :start_connected => true,
        :address         => "00:1a:4a:16:01:53"
      )
      # nic.lan.should == @lan # TODO: Hook up this connection

      expect(v.parent_datacenter).to have_attributes(
        :ems_ref     => "/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :ems_ref_obj => "/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :uid_ems     => "b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :name        => "dc1",
        :type        => "Datacenter",
        :folder_path => "Datacenters/dc1"
      )

      expect(v.parent_folder).to have_attributes(
        :ems_ref     => nil,
        :ems_ref_obj => nil,
        :uid_ems     => "root_dc",
        :name        => "Datacenters",
        :type        => nil,
        :folder_path => "Datacenters"
      )

      expect(v.parent_blue_folder).to have_attributes(
        :ems_ref     => nil,
        :ems_ref_obj => nil,
        :uid_ems     => "b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1_vm",
        :name        => "vm",
        :type        => nil,
        :folder_path => "Datacenters/dc1/vm"
      )
    end

    def assert_specific_template
      v = ManageIQ::Providers::Redhat::InfraManager::Template.find_by(:name => "template_cd1")
      expect(v).to have_attributes(
        :template              => true,
        :ems_ref               => "/api/templates/785e845e-baa0-4812-8a8c-467f37ad6c79",
        :ems_ref_obj           => "/api/templates/785e845e-baa0-4812-8a8c-467f37ad6c79",
        :uid_ems               => "785e845e-baa0-4812-8a8c-467f37ad6c79",
        :vendor                => "redhat",
        :power_state           => "never",
        :location              => "785e845e-baa0-4812-8a8c-467f37ad6c79.ovf",
        :tools_status          => nil,
        :boot_time             => nil,
        :standby_action        => nil,
        :connection_state      => "connected",
        :cpu_affinity          => nil,
        :memory_reserve        => 4024,
        :memory_reserve_expand => nil,
        :memory_limit          => 16_096,
        :memory_shares         => nil,
        :memory_shares_level   => nil,
        :cpu_reserve           => nil,
        :cpu_reserve_expand    => nil,
        :cpu_limit             => nil,
        :cpu_shares            => nil,
        :cpu_shares_level      => nil
      )

      expect(v.ext_management_system).to eq(@ems)
      expect(v.ems_cluster).to eq(@cluster)
      expect(v.parent_resource_pool).to  be_nil
      expect(v.host).to                  be_nil
      expect(v.storages).to eq([@storage]) # CHECK MANUALLY
      # v.storage  # TODO: Fix bug where duplication location GUIDs could cause the wrong value to appear.

      expect(v.operating_system).to have_attributes(
        :product_name => "other"
      )

      expect(v.custom_attributes.size).to eq(0)
      expect(v.snapshots.size).to eq(0)

      expect(v.hardware).to have_attributes(
        :guest_os             => "other",
        :guest_os_full_name   => nil,
        :bios                 => nil,
        :cpu_cores_per_socket => 1,
        :cpu_total_cores      => 4,
        :cpu_sockets          => 4,
        :annotation           => nil,
        :memory_mb            => 4024
      )

      expect(v.hardware.disks.size).to eq(1)

      disk = v.hardware.disks.find_by(:device_name => "vm1_Disk1")
      expect(disk).to have_attributes(
        :device_name     => "vm1_Disk1",
        :device_type     => "disk",
        :controller_type => "virtio",
        :present         => true,
        :filename        => "7917730e-39fb-4da4-9256-da652c33e5b6",
        :location        => "0",
        :size            => 6_442_450_944,
        :size_on_disk    => 1_838_448_640,
        :mode            => "persistent",
        :disk_type       => "thin",
        :start_connected => true
      )
      expect(disk.storage).to eq(@storage) ## CHECK MANUALLY

      expect(v.hardware.guest_devices.size).to eq(0)
      expect(v.hardware.nics.size).to eq(0)
      expect(v.hardware.networks.size).to eq(0)

      expect(v.parent_datacenter).to have_attributes(
        :ems_ref     => "/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :ems_ref_obj => "/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :uid_ems     => "b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1",
        :name        => "dc1",
        :type        => "Datacenter",
        :folder_path => "Datacenters/dc1"
      )

      expect(v.parent_folder).to have_attributes(
        :ems_ref     => nil,
        :ems_ref_obj => nil,
        :uid_ems     => "root_dc",
        :name        => "Datacenters",
        :type        => nil,
        :folder_path => "Datacenters"
      )

      expect(v.parent_blue_folder).to have_attributes(
        :ems_ref     => nil,
        :ems_ref_obj => nil,
        :uid_ems     => "b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1_vm",
        :name        => "vm",
        :type        => nil,
        :folder_path => "Datacenters/dc1/vm"
      )
    end

    def assert_relationship_tree
      expect(@ems.descendants_arranged).to match_relationship_tree(
        [EmsFolder, "Datacenters", {:hidden=>true}] => {
          [Datacenter, "Default"] => {
            [EmsFolder, "host", {:hidden=>true}] => {
              [EmsCluster, "Default"] => {
                [ResourcePool, "Default for Cluster Default"] => {}
              }
            }, [EmsFolder, "vm", {:hidden=>true}] => {
              [ManageIQ::Providers::Redhat::InfraManager::Template, "template_ex_default"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Template, "test_template_1"] => {}
            }
          }, [Datacenter, "dc1"] => {
            [EmsFolder, "host", {:hidden=>true}] => {
              [EmsCluster, "cc1"] => {
                [ResourcePool, "Default for Cluster cc1"] => {
                  [ManageIQ::Providers::Redhat::InfraManager::Vm, "iso_t2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "iso_t3"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "iso_test_4"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_gaps_p2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_a1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_a2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_b3"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_b5"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_b6"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_c1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_f2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_f5"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm2"] => {}
                }
              }, [EmsCluster, "dccc2"] => {
                [ResourcePool, "Default for Cluster dccc2"] => {}
              }
            }, [EmsFolder, "vm", {:hidden=>true}] => {
              [ManageIQ::Providers::Redhat::InfraManager::Template, "template_cd1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "iso_t2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "iso_t3"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "iso_test_4"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_gaps_p2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_a1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_a2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_b3"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_b5"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_b6"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_c1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_f2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "test_iso_f5"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm2"] => {}
            }
          }
        }
      )
    end
  end
end
