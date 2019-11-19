require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'pluto-vdsg.eng.lab.tlv.redhat.com', :ipaddress => '10.35.19.13', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording.yml')

    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
  end

  it "will perform a full refresh on v4.1" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.parent.name.underscore}/refresh/refresher_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload
    aggregate_failures "tests" do
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
  end

  it "will perform a refresh and reconnect a host" do
    FactoryBot.create(:host_redhat,
                       :ext_management_system => nil,
                       :ems_ref               => "/api/hosts/ce40bb38-f10a-43f3-8e15-d0ffad692a19",
                       :ems_ref_obj           => "/api/hosts/ce40bb38-f10a-43f3-8e15-d0ffad692a19",
                       :name                  => "bodh1",
                       :hostname              => "bodh1.usersys.redhat.com",
                       :ipaddress             => "10.35.19.12",
                       :uid_ems               => "ce40bb38-f10a-43f3-8e15-d0ffad692a19")

    EmsRefresh.refresh(@ems)
    @ems.reload

    host = Host.find_by(:name => "bodh1")
    expect(host.ext_management_system).to eq(@ems)
    expect(Host.where(:uid_ems => "ce40bb38-f10a-43f3-8e15-d0ffad692a19").count).to eq 1
  end

  it "will perform a refresh and reconnect a vm" do
    @vm = FactoryBot.create(:vm_redhat,
                             :ext_management_system => nil,
                             :ems_ref               => "/api/vms/8070fa6d-5b82-412c-9d41-a00017205c73",
                             :ems_ref_obj           => "/api/vms/8070fa6d-5b82-412c-9d41-a00017205c73",
                             :uid_ems               => "8070fa6d-5b82-412c-9d41-a00017205c73",
                             :vendor                => "redhat",
                             :raw_power_state       => "up",
                             :location              => "8070fa6d-5b82-412c-9d41-a00017205c73.ovf")

    EmsRefresh.refresh(@ems)
    @ems.reload

    vm = VmOrTemplate.find_by(:uid_ems => "8070fa6d-5b82-412c-9d41-a00017205c73")
    expect(vm.ext_management_system).to eq(@ems)
    expect(VmOrTemplate.where(:uid_ems => "8070fa6d-5b82-412c-9d41-a00017205c73").count).to eq 1
  end

  it 'preserve last boot time after vm refresh' do
    vm = FactoryBot.create(:vm_redhat,
                           :ext_management_system => @ems,
                           :ems_ref               => "/api/vms/1010ec66-5d68-4ae6-b72b-824f5885259d",
                           :ems_ref_obj           => "/api/vms/1010ec66-5d68-4ae6-b72b-824f5885259d",
                           :uid_ems               => "1010ec66-5d68-4ae6-b72b-824f5885259d",
                           :vendor                => "redhat",
                           :boot_time             => Time.zone.parse("2017-08-02T06:53:36.148"),
                           :raw_power_state       => "up")

    EmsRefresh.refresh(@ems)
    @ems.reload

    refresh_vm = VmOrTemplate.find_by(:uid_ems => "1010ec66-5d68-4ae6-b72b-824f5885259d")
    expect(refresh_vm.boot_time).to eq(vm.boot_time)
  end

  def assert_table_counts(_lan_number)
    expect(ExtManagementSystem.count).to eq(2)
    expect(EmsFolder.count).to eq(7)
    expect(EmsCluster.count).to eq(3)
    expect(Host.count).to eq(2)
    expect(ResourcePool.count).to eq(3)
    expect(VmOrTemplate.count).to eq(4)
    expect(Vm.count).to eq(2)
    expect(MiqTemplate.count).to eq(2)
    expect(Storage.count).to eq(7)

    expect(CustomAttribute.count).to eq(0) # TODO: 3.0 spec has values for this
    expect(CustomizationSpec.count).to eq(0)
    expect(Disk.count).to eq(4)
    expect(GuestDevice.count).to eq(4)
    expect(Hardware.count).to eq(6)
    expect(Lan.count).to eq(2)
    expect(MiqScsiLun.count).to eq(0)
    expect(MiqScsiTarget.count).to eq(0)
    expect(Network.count).to eq(4)
    expect(OperatingSystem.count).to eq(6)
    expect(Snapshot.count).to eq(3)
    expect(Switch.count).to eq(3)
    expect(SystemService.count).to eq(0)

    expect(Relationship.count).to eq(20)
    expect(MiqQueue.count).to eq(8)

    expect(CloudNetwork.count).to eq(6)
    expect(CloudSubnet.count).to eq(2)
    expect(NetworkRouter.count).to eq(1)
    expect(NetworkPort.count).to eq(1)
  end

  def assert_ems
    expect(@ems).to have_attributes(
      :api_version => "4.2.0",
      :uid_ems     => nil
    )

    expect(@ems.ems_folders.size).to eq(7)
    expect(@ems.ems_clusters.size).to eq(3)
    expect(@ems.resource_pools.size).to eq(3)
    expect(@ems.storages.size).to eq(6)
    expect(@ems.hosts.size).to eq(2)
    expect(@ems.vms_and_templates.size).to eq(4)
    expect(@ems.vms.size).to eq(2)
    expect(@ems.miq_templates.size).to eq(2)

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
      :ems_ref                   => "b85981f3-b7d0-4ed1-8b1b-94708b472b17",
      :shared                    => nil,
      :status                    => "active",
      :enabled                   => nil,
      :external_facing           => nil,
      :orchestration_stack       => nil,
      :provider_physical_network => nil,
      :provider_network_type     => nil,
      :provider_segmentation_id  => nil,
      :port_security_enabled     => false,
      :qos_policy_id             => nil,
      :vlan_transparent          => nil,
      :maximum_transmission_unit => 1442
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
      :ems_ref                        => "4c9b5697-8562-420b-972c-d3bbeb10f11e",
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
      :ems_ref               => "38dbd81b-bb7c-4fd2-9e7e-a1a8cfeb4312",
      :admin_state_up        => "t",
      :status                => "INACTIVE",
      :external_gateway_info => nil,
      :distributed           => nil,
      :routes                => [],
      :high_availability     => nil,
      :cloud_tenant_id       => @cloud_tenant.id,
      :cloud_network         => nil
    )
  end

  def assert_specific_network_port
    @port = NetworkPort.find_by(:name => "nic1")
    expect(@port).to have_attributes(
      :ems_id                            => @ems.network_manager.id,
      :type                              => "ManageIQ::Providers::Openstack::NetworkManager::NetworkPort",
      :name                              => "nic1",
      :ems_ref                           => "2500800a-9dec-4fea-a7ec-a6fdb836da0a",
      :admin_state_up                    => true,
      :status                            => nil,
      :mac_address                       => "00:1a:4a:16:01:00",
      :device_owner                      => "oVirt",
      :device_ref                        => "3b31db55-96cc-4b0b-b820-c693139cbaf9",
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
    @cluster = EmsCluster.find_by(:name => 'newd1_cluster')
    expect(@cluster).to have_attributes(
      :ems_ref                 => "/api/clusters/1c273044-e6ca-492f-9ac2-47381b626808",
      :ems_ref_obj             => "/api/clusters/1c273044-e6ca-492f-9ac2-47381b626808",
      :uid_ems                 => "1c273044-e6ca-492f-9ac2-47381b626808",
      :name                    => "newd1_cluster",
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
      :name                  => "Default for Cluster newd1_cluster",
      :type                  => "ManageIQ::Providers::Redhat::InfraManager::ResourcePool",
      :uid_ems               => "1c273044-e6ca-492f-9ac2-47381b626808_respool",
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
    @storage = Storage.find_by(:name => "data_spider_1")
    expect(@storage).to have_attributes(
      :ems_ref                       => "/api/storagedomains/723b4112-1502-4b01-83a7-2ba87d1bbb35",
      :ems_ref_obj                   => "/api/storagedomains/723b4112-1502-4b01-83a7-2ba87d1bbb35",
      :name                          => "data_spider_1",
      :store_type                    => "NFS",
      :total_space                   => 53_687_091_200,
      :free_space                    => 37_580_963_840,
      :uncommitted                   => 40_802_189_312,
      :multiplehostaccess            => 1, # TODO: Should this be a boolean column?
      :location                      => "vserver-spider.eng.lab.tlv.redhat.com:/vol/vol_bodnopoz/data1",
      :directory_hierarchy_supported => nil,
      :thin_provisioning_supported   => nil,
      :raw_disk_mappings_supported   => nil
    )

    @storage2 = Storage.find_by(:name => "venus-data-1")
    expect(@storage2).to have_attributes(
      :ems_ref                       => "/api/storagedomains/26c8cd54-65d4-424f-a870-8145439bba1c",
      :ems_ref_obj                   => "/api/storagedomains/26c8cd54-65d4-424f-a870-8145439bba1c",
      :name                          => "venus-data-1",
      :store_type                    => "NFS",
      :total_space                   => 207_232_172_032,
      :free_space                    => 168_577_466_368,
      :uncommitted                   => 207_232_172_032,
      :multiplehostaccess            => 1, # TODO: Should this be a boolean column?
      :location                      => "venus-vdsb.usersys.redhat.com:/home/nfsshare/boris/master/data2",
      :directory_hierarchy_supported => nil,
      :thin_provisioning_supported   => nil,
      :raw_disk_mappings_supported   => nil
    )

    def assert_specific_host
      @host = ManageIQ::Providers::Redhat::InfraManager::Host.find_by(:name => "bodh1")
      expect(@host).to have_attributes(
        :ems_ref          => "/api/hosts/ce40bb38-f10a-43f3-8e15-d0ffad692a19",
        :ems_ref_obj      => "/api/hosts/ce40bb38-f10a-43f3-8e15-d0ffad692a19",
        :name             => "bodh1",
        :hostname         => "bodh1.usersys.redhat.com",
        :ipaddress        => "10.46.10.132",
        :uid_ems          => "ce40bb38-f10a-43f3-8e15-d0ffad692a19",
        :vmm_vendor       => "redhat",
        :vmm_version      => "7.6",
        :vmm_product      => "rhel",
        :vmm_buildnumber  => nil,
        :power_state      => "on",
        :maintenance      => false,
        :connection_state => "connected"
      )

      @host_cluster = EmsCluster.find_by(:ems_ref => "/api/clusters/1c273044-e6ca-492f-9ac2-47381b626808")
      expect(@host.ems_cluster).to eq(@host_cluster)
      expect(@host.storages.size).to eq(3)
      expect(@host.storages).to include(@storage) ### MIGHT BE WRONG, CHECK MANUALLY

      expect(@host.operating_system).to have_attributes(
        :name         => "bodh1.usersys.redhat.com",
        :product_name => "RHEL",
        :version      => "7.6 - 4.el7",
        :build_number => nil,
        :product_type => "linux"
      )

      expect(@host.system_services.size).to eq(0)

      expect(@host.switches.size).to eq(1)

      switch = @host.switches.first
      expect(switch).to have_attributes(
        :uid_ems           => "f46b7c46-6196-4750-a07f-bfeab9f1c275",
        :name              => "ovirtmgmt",
        :ports             => nil,
        :allow_promiscuous => nil,
        :forged_transmits  => nil,
        :mac_changes       => nil
      )

      expect(switch.lans.size).to eq(1)

      @lan = switch.lans.first
      expect(@lan).to have_attributes(
        :uid_ems                    => "4ec7ba24-c6bf-42fc-9975-d6a9bf3f01cf",
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
        :cpu_speed            => 2100,
        :cpu_type             => "Intel Xeon Processor (Skylake)",
        :manufacturer         => "Red Hat",
        :model                => "RHEV Hypervisor",
        :number_of_nics       => 1,
        :memory_mb            => 3787,
        :memory_console       => nil,
        :cpu_sockets          => 2,
        :cpu_total_cores      => 2,
        :cpu_cores_per_socket => 1,
        :guest_os             => nil,
        :guest_os_full_name   => nil,
        :vmotion_enabled      => nil,
        :cpu_usage            => nil,
        :memory_usage         => nil,
        :serial_number        => "4c4c4544-0037-4610-8057-b7c04f325332"
      )

      expect(@host.hardware.networks.size).to eq(1)

      network = @host.hardware.networks.find_by(:description => "eth0")
      expect(network).to have_attributes(
        :description  => "eth0",
        :dhcp_enabled => nil,
        :ipaddress    => "10.46.10.132",
        :subnet_mask  => "255.255.252.0"
      )

      # TODO: Verify this host should have 3 nics, 2 cdroms, 1 floppy, any storage adapters?
      expect(@host.hardware.guest_devices.size).to eq(1)

      expect(@host.hardware.nics.size).to eq(1)
      nic = @host.hardware.nics.first

      expect(nic).to have_attributes(
        :uid_ems         => "7b77f307-6dda-4e04-ad09-7c05fa6a9305",
        :device_name     => "eth0",
        :device_type     => "ethernet",
        :location        => "0",
        :present         => true,
        :controller_type => "ethernet"
      )

      expect(nic.switch).to eq(switch)
      expect(nic.network).to eq(network)

      expect(@host.hardware.storage_adapters.size).to eq(0)
    end

    def assert_specific_vm_powered_on
      v = ManageIQ::Providers::Redhat::InfraManager::Vm.find_by(:name => "vm_on")
      expect(v).to have_attributes(
        :template              => false,
        :uid_ems               => "a1293e54-dae8-496f-baa4-27719592113e",
        :vendor                => "redhat",
        :raw_power_state       => "up",
        :power_state           => "on",
        :tools_status          => nil,
        :boot_time             => Time.zone.parse("2019-08-21T06:51:52.775"),
        :standby_action        => nil,
        :connection_state      => "connected",
        :cpu_affinity          => nil,
        :memory_reserve_expand => nil,
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

      host = ManageIQ::Providers::Redhat::InfraManager::Host.find_by(:name => "bodh1")
      expect(v.host).to eq(host)
      expect(v.storages).to eq([@storage])

      expect(v.operating_system).to have_attributes(
        :product_name => "other"
      )

      expect(v.hostnames).to match_array(["dhcp-8-199.lab.eng.tlv2.redhat.com"])
      expect(v.custom_attributes.size).to eq(0)

      expect(v.snapshots.size).to eq(2)

      snapshot = v.snapshots.detect { |s| s.uid == "fc082077-576c-4f06-a9cc-be2c3bd8f2d9" }
      expect(snapshot).to have_attributes(
        :uid         => "fc082077-576c-4f06-a9cc-be2c3bd8f2d9",
        :parent_uid  => "395ead74-54f9-4f16-88bb-21a7a1e4924e",
        :uid_ems     => "fc082077-576c-4f06-a9cc-be2c3bd8f2d9",
        :name        => "Active VM",
        :description => "Active VM",
        :current     => 1,
        :total_size  => nil,
        :filename    => nil
      )
      snapshot_parent = ::Snapshot.find_by(:name => "vm_on_snap_1")
      expect(snapshot.parent).to eq(snapshot_parent)
      expect(snapshot_parent.current).to eq(0)

      expect(v.hardware).to have_attributes(
        :guest_os             => "other",
        :guest_os_full_name   => nil,
        :bios                 => nil,
        :cpu_cores_per_socket => 1,
        :cpu_total_cores      => 2,
        :cpu_sockets          => 2,
        :annotation           => "",
        :memory_mb            => 2048
      )

      expect(v.hardware.disks.size).to eq(1)
      disk = v.hardware.disks.find_by(:device_name => "GlanceDisk-fe03ebf")
      expect(disk).to have_attributes(
        :device_name     => "GlanceDisk-fe03ebf",
        :device_type     => "disk",
        :controller_type => "virtio",
        :present         => true,
        :filename        => "08b054b2-0001-4dd6-9cf2-434213c02fbe",
        :location        => "0",
        :size            => 8_589_934_592,
        :size_on_disk    => 2_561_437_696,
        :mode            => "persistent",
        :disk_type       => "thin",
        :start_connected => true
      )
      expect(disk.storage).to eq(@storage)

      expect(v.hardware.guest_devices.size).to eq(1)
      expect(v.hardware.nics.size).to eq(1)

      nic = v.hardware.nics.find_by(:device_name => "nic1")
      expect(nic).to have_attributes(
        :uid_ems         => "40c3c841-74be-461f-ac6c-25df73c1b40b",
        :device_name     => "nic1",
        :device_type     => "ethernet",
        :controller_type => "ethernet",
        :present         => true,
        :start_connected => true,
        :address         => "00:1a:4a:16:01:05"
      )
      nic.lan == @lan

      expect(v.ipaddresses).to match_array(["10.46.8.199", "2620:52:0:2e08:21a:4aff:fe16:105", "fe80::21a:4aff:fe16:105"])

      guest_device = v.hardware.guest_devices.find_by(:device_name => "nic1")
      expect(guest_device.network).not_to be_nil
      expect(guest_device.network).to have_attributes(
        :hostname    => "dhcp-8-199.lab.eng.tlv2.redhat.com",
        :ipaddress   => "10.46.8.199",
        :ipv6address => "2620:52:0:2e08:21a:4aff:fe16:105"
      )

      expect(v.hardware.networks.size).to eq(2)

      network = v.hardware.networks.find_by(:ipv6address => "2620:52:0:2e08:21a:4aff:fe16:105")
      expect(network).not_to be_nil
      expect(network).to have_attributes(
        :ipaddress => "10.46.8.199",
        :hostname  => "dhcp-8-199.lab.eng.tlv2.redhat.com"
      )

      expect(v.parent_datacenter).to have_attributes(
        :ems_ref     => "/api/datacenters/944df9ee-3274-43c4-908f-8c35e59e483b",
        :ems_ref_obj => "/api/datacenters/944df9ee-3274-43c4-908f-8c35e59e483b",
        :uid_ems     => "944df9ee-3274-43c4-908f-8c35e59e483b",
        :name        => "newd1",
        :type        => "Datacenter",
        :folder_path => "Datacenters/newd1"
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
        :uid_ems     => "944df9ee-3274-43c4-908f-8c35e59e483b_vm",
        :name        => "vm",
        :type        => nil,
        :folder_path => "Datacenters/newd1/vm"
      )
    end

    def assert_specific_vm_powered_off
      v = ManageIQ::Providers::Redhat::InfraManager::Vm.find_by(:name => "vm_off")
      expect(v).to have_attributes(
        :template              => false,
        :ems_ref               => "/api/vms/8070fa6d-5b82-412c-9d41-a00017205c73",
        :ems_ref_obj           => "/api/vms/8070fa6d-5b82-412c-9d41-a00017205c73",
        :uid_ems               => "8070fa6d-5b82-412c-9d41-a00017205c73",
        :vendor                => "redhat",
        :raw_power_state       => "down",
        :power_state           => "off",
        :location              => "8070fa6d-5b82-412c-9d41-a00017205c73.ovf",
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
        :uid         => "e4a01e51-c7dc-4cfd-b1c3-b3cb0653333c",
        :uid_ems     => "e4a01e51-c7dc-4cfd-b1c3-b3cb0653333c",
        :parent_uid  => nil,
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
        :cpu_total_cores      => 1,
        :cpu_sockets          => 1,
        :annotation           => "",
        :memory_mb            => 1024
      )

      expect(v.hardware.disks.size).to eq(1)

      disk = v.hardware.disks.find_by(:device_name => "GlanceDisk-34bec3e")
      expect(disk).to have_attributes(
        :device_name     => "GlanceDisk-34bec3e",
        :device_type     => "disk",
        :controller_type => "virtio",
        :present         => true,
        :filename        => "738dc6a9-c7ff-4bd4-8f37-d0e4fdc0ff76",
        :location        => "0",
        :size            => 46_137_344,
        :size_on_disk    => 204_800,
        :mode            => "persistent",
        :disk_type       => "thin",
        :start_connected => true
      )
      expect(disk.storage).to eq(@storage) ## CHECK MANUALLY

      expect(v.hardware.guest_devices.size).to eq(1)
      expect(v.hardware.nics.size).to eq(1)

      nic = v.hardware.nics.find_by(:device_name => "nic1")
      expect(nic).to have_attributes(
        :uid_ems         => "fee0cbf3-e81f-4b5e-a0d4-1ad3e1210951",
        :device_name     => "nic1",
        :device_type     => "ethernet",
        :controller_type => "ethernet",
        :present         => true,
        :start_connected => true,
        :address         => "00:1a:4a:16:01:04"
      )
      nic.lan == @lan

      expect(v.parent_datacenter).to have_attributes(
        :ems_ref     => "/api/datacenters/944df9ee-3274-43c4-908f-8c35e59e483b",
        :ems_ref_obj => "/api/datacenters/944df9ee-3274-43c4-908f-8c35e59e483b",
        :folder_path => "Datacenters/newd1",
        :name        => "newd1",
        :type        => "Datacenter",
        :uid_ems     => "944df9ee-3274-43c4-908f-8c35e59e483b"
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
        :uid_ems     => "944df9ee-3274-43c4-908f-8c35e59e483b_vm",
        :name        => "vm",
        :type        => nil,
        :folder_path => "Datacenters/newd1/vm"
      )
    end

    def assert_specific_template
      v = ManageIQ::Providers::Redhat::InfraManager::Template.find_by(:name => "template_cd1")
      expect(v).to have_attributes(
        :template              => true,
        :ems_ref               => "/api/templates/bcdd6891-68c9-4629-8c72-668c2353ab11",
        :ems_ref_obj           => "/api/templates/bcdd6891-68c9-4629-8c72-668c2353ab11",
        :uid_ems               => "bcdd6891-68c9-4629-8c72-668c2353ab11",
        :vendor                => "redhat",
        :power_state           => "never",
        :location              => "bcdd6891-68c9-4629-8c72-668c2353ab11.ovf",
        :tools_status          => nil,
        :boot_time             => nil,
        :standby_action        => nil,
        :connection_state      => "connected",
        :cpu_affinity          => nil,
        :memory_reserve_expand => nil,
        :memory_limit          => 4096,
        :memory_reserve        => 1024,
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
        :cpu_total_cores      => 1,
        :cpu_sockets          => 1,
        :annotation           => "CirrOS 0.4.0 for x86_64 (34bec3e)",
        :memory_mb            => 1024
      )

      expect(v.hardware.disks.size).to eq(1)

      disk = v.hardware.disks.find_by(:device_name => "GlanceDisk-34bec3e")
      expect(disk).to have_attributes(
        :device_name     => "GlanceDisk-34bec3e",
        :device_type     => "disk",
        :controller_type => "virtio",
        :present         => true,
        :filename        => "2d41b00f-d594-47dd-9148-931731ddf8ff",
        :location        => "0",
        :size            => 46_137_344,
        :size_on_disk    => 12_775_424,
        :mode            => "persistent",
        :disk_type       => "thin",
        :start_connected => true
      )
      expect(disk.storage).to eq(@storage)

      expect(v.hardware.guest_devices.size).to eq(0)
      expect(v.hardware.nics.size).to eq(0)
      expect(v.hardware.networks.size).to eq(0)

      expect(v.parent_datacenter).to have_attributes(
        :ems_ref     => "/api/datacenters/944df9ee-3274-43c4-908f-8c35e59e483b",
        :ems_ref_obj => "/api/datacenters/944df9ee-3274-43c4-908f-8c35e59e483b",
        :folder_path => "Datacenters/newd1",
        :name        => "newd1",
        :type        => "Datacenter",
        :uid_ems     => "944df9ee-3274-43c4-908f-8c35e59e483b"
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
        :uid_ems     => "944df9ee-3274-43c4-908f-8c35e59e483b_vm",
        :name        => "vm",
        :type        => nil,
        :folder_path => "Datacenters/newd1/vm"
      )
    end

    def assert_relationship_tree
      expect(@ems.descendants_arranged).to match_relationship_tree(
        [EmsFolder, "Datacenters", {:hidden=>true}] => {
          [Datacenter, "Newd"] => {
            [EmsFolder, "host", {:hidden=>true}] => {
              [ManageIQ::Providers::Redhat::InfraManager::Cluster, "newc"] => {
                [ManageIQ::Providers::Redhat::InfraManager::ResourcePool, "Default for Cluster newc"] => {}
              }
            }, [EmsFolder, "vm", {:hidden=>true}] => {}
          }, [Datacenter, "newd1"] => {
            [EmsFolder, "host", {:hidden=>true}] => {
              [ManageIQ::Providers::Redhat::InfraManager::Cluster, "newd1_cluster"] => {
                [ManageIQ::Providers::Redhat::InfraManager::ResourcePool, "Default for Cluster newd1_cluster"] => {
                  [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm_off"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm_on"] => {}
                }
              },
            }, [EmsFolder, "vm", {:hidden=>true}] => {
              [ManageIQ::Providers::Redhat::InfraManager::Template, "template_cd1"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Template, "template_cd2"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm_off"] => {}, [ManageIQ::Providers::Redhat::InfraManager::Vm, "vm_on"] => {}
            }
          }
        }
      )
    end
  end
end
