describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  context 'targeted refresh of a Vm' do
    let(:ip_address) { '192.168.1.31' }
    let(:add_vm_event) do
      {
        :id          => "668",
        :href        => "/ovirt-engine/api/events/668",
        :cluster     => {
          :id   => "00000002-0002-0002-0002-0000000001e9",
          :href => "/api/clusters/00000002-0002-0002-0002-0000000001e9"
        },
        :data_center => {
          :id   => "00000001-0001-0001-0001-000000000311",
          :href => "/ovirt-engine/api/datacenters/00000001-0001-0001-0001-000000000311"
        },
        :template    => {
          :id   => "6160a62c-a43f-4ffc-896b-93d98f55e9ef",
          :href => "/ovirt-engine/api/templates/6160a62c-a43f-4ffc-896b-93d98f55e9ef"
        },
        :user        => {
          :id   => "58d90d4c-00cb-00bf-03bd-000000000320",
          :href => "/ovirt-engine/api/users/58d90d4c-00cb-00bf-03bd-000000000320"
        },
        :vm          => {
          :id   => "22f18a6b-fc44-43ae-976f-993ad5f1d648",
          :href => "/ovirt-engine/api/vms/22f18a6b-fc44-43ae-976f-993ad5f1d648"
        },
        :description => "VM test2 creation has been completed.",
        :severity    => "normal",
        :code        => 53,
        :time        => "2017-04-19 12:55:52 +0200",
        :name        => "USER_ADD_VM_FINISHED_SUCCESS"
      }
    end

    before(:each) do
      _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryBot.create(:ems_redhat, :zone => zone, :hostname => ip_address, :ipaddress => ip_address,
                                :port => 8443)
      @ems.update_authentication(:default => {:userid => "admin@internal", :password => "engine"})

      @cluster = FactoryBot.create(:ems_cluster,
                                    :ems_ref => "/api/clusters/00000002-0002-0002-0002-0000000001e9",
                                    :uid_ems => "00000002-0002-0002-0002-0000000001e9",
                                    :ems_id  => @ems.id,
                                    :name    => "Default")

      allow(@ems).to receive(:supported_api_versions).and_return([3])
      stub_settings_merge(
        :ems => {
          :ems_redhat => {
            :use_ovirt_engine_sdk => false,
            :resolve_ip_addresses => false
          }
        }
      )
    end

    it "should refresh a vm" do
      storage = FactoryBot.create(:storage,
                                   :ems_ref  => "/api/storagedomains/ee745353-c069-4de8-8d76-ec2e155e2ca0",
                                   :location => "192.168.1.106:/home/pkliczewski/export/hosted")

      disk = FactoryBot.create(:disk,
                                :storage  => storage,
                                :filename => "da123bb9-095a-4933-95f2-8032dfa332e1")
      hardware = FactoryBot.create(:hardware,
                                    :disks => [disk])

      vm = FactoryBot.create(:vm_redhat,
                              :ext_management_system => @ems,
                              :uid_ems               => "4f6dd4c3-5241-494f-8afc-f1c67254bf77",
                              :ems_cluster           => @cluster,
                              :ems_ref               => "/api/vms/4f6dd4c3-5241-494f-8afc-f1c67254bf77",
                              :storage               => storage,
                              :storages              => [storage],
                              :hardware              => hardware)

      VCR.use_cassette("#{described_class.name.underscore}_target_vm") do
        EmsRefresh.refresh(vm)
      end

      assert_table_counts
      assert_vm(vm, storage)
      assert_vm_rels(vm, hardware, storage)
      assert_cluster(vm)
      assert_storage(storage, vm)
    end

    it "should refresh new vm" do
      allow(@ems.ovirt_services).to receive(:cluster_name_href).with(@cluster.ems_ref).and_return(@cluster.name)
      allow(@ems.refresher).to      receive(:refresh)

      description = add_vm_event[:description]
      name        = add_vm_event[:name]

      ep_class = ManageIQ::Providers::Redhat::InfraManager::EventParser
      target_hash, target_klass, target_find = ep_class.parse_new_target(add_vm_event, description, @ems, name)

      new_vm = VCR.use_cassette("#{described_class.name.underscore}_target_new_vm", :allow_unused_http_interactions => true) do
        EmsRefresh.refresh_new_target(@ems.id, target_hash, target_klass, target_find)
      end

      # Check the new vm's uid matches the event
      expect(new_vm.uid_ems).to eq(add_vm_event[:vm][:id])

      # Check that the new vm is linked up to a cluster
      expect(new_vm.ems_cluster).not_to     be_nil
      expect(new_vm.ems_cluster.uid_ems).to eq(add_vm_event[:cluster][:id])

      # Check that the vm and cluster are linked to a datacenter
      expect(new_vm.parent_datacenter).not_to             be_nil
      expect(new_vm.ems_cluster.parent_datacenter).not_to be_nil

      expect(new_vm.parent_datacenter.uid_ems).to             eq(add_vm_event[:data_center][:id])
      expect(new_vm.ems_cluster.parent_datacenter.uid_ems).to eq(add_vm_event[:data_center][:id])
    end
  end

  context 'targeted refresh after vm migration' do
    let(:ip_address) { '10.35.161.51' }

    before(:each) do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryBot.create(:ems_redhat, :zone => zone,
                                :hostname => ip_address, :ipaddress => ip_address, :port => 443)
      @ems.update_authentication(:default => {:userid => "admin@internal", :password => "password"})
      allow(@ems).to receive(:supported_api_versions).and_return(['3'])
      stub_settings_merge(
        :ems => {
          :ems_redhat => {
            :resolve_ip_addresses => false
          }
        }
      )
    end

    it 'should save the vms new host' do
      VCR.use_cassette("#{described_class.name.underscore}_before_migration") do
        EmsRefresh.refresh(@ems)
      end
      @ems.reload
      vm = @ems.vms.where(:name => "migrate_test_1").first
      expect(vm.host.name).to eq("pluto-vdsg.eng.lab.tlv.redhat.com")
      expect(vm.host.ems_ref).to eq("/api/hosts/0b4c3cf3-3b51-479a-bd36-ab968151a9a9")

      assert_host(vm.host)

      VCR.use_cassette("#{described_class.name.underscore}_after_migration", :allow_unused_http_interactions => true) do
        EmsRefresh.refresh(vm)
      end

      vm.reload

      # Check that the VM is on a new host
      expect(vm.host.name).to eq("lilach-vdsa.tlv.redhat.com")
      expect(vm.host.ems_ref).to eq("/api/hosts/bfb0c0b4-8616-4bbf-9210-9de48892adc6")

      # And everything else about the hosts are the same
      assert_host(vm.host)
    end

    def assert_host(host)
      expect(host.ems_cluster).not_to be_nil
      expect(host.ems_cluster.name).to eq("Default")

      expect(host.storages.count).to eq(1)

      storage = host.storages.find_by(:name => "data1_new")
      expect(storage.ems_ref).to eq("/api/storagedomains/2ef34a5b-2046-4707-9180-7723aad1b8ce")

      expect(host.lans.count).to eq(2)
      lan = host.lans.find_by(:name => "rhevm")
      expect(lan.name).to eq("rhevm")

      expect(host.switches.count).to eq(2)
      switch = host.switches.find_by(:name => "rhevm")
      expect(switch.name).to eq("rhevm")
      expect(switch.lans).to include(lan)
    end
  end

  def assert_table_counts
    expect(ExtManagementSystem.count).to eq(1)
    expect(EmsCluster.count).to eq(1)
    expect(ResourcePool.count).to eq(1)
    expect(Vm.count).to eq(1)
    expect(Storage.count).to eq(1)
    expect(Disk.count).to eq(1)
    expect(GuestDevice.count).to eq(1)
    expect(Hardware.count).to eq(1)
    expect(OperatingSystem.count).to eq(1)
    expect(Snapshot.count).to eq(1)
    expect(Datacenter.count).to eq(1)

    expect(Relationship.count).to eq(9)
    expect(MiqQueue.count).to eq(4)
  end

  def assert_vm(vm, storage)
    vm.reload
    expect(vm).to have_attributes(
      :template               => false,
      :ems_ref                => "/api/vms/4f6dd4c3-5241-494f-8afc-f1c67254bf77",
      :ems_ref_obj            => "/api/vms/4f6dd4c3-5241-494f-8afc-f1c67254bf77",
      :uid_ems                => "4f6dd4c3-5241-494f-8afc-f1c67254bf77",
      :vendor                 => "redhat",
      :raw_power_state        => "down",
      :power_state            => "off",
      :connection_state       => "connected",
      :name                   => "123",
      :format                 => nil,
      :version                => nil,
      :description            => nil,
      :location               => "4f6dd4c3-5241-494f-8afc-f1c67254bf77.ovf",
      :config_xml             => nil,
      :autostart              => nil,
      :host_id                => nil,
      :last_sync_on           => nil,
      :storage_id             => storage.id,
      :last_scan_on           => nil,
      :last_scan_attempt_on   => nil,
      :retires_on             => nil,
      :retired                => nil,
      :boot_time              => nil,
      :tools_status           => nil,
      :standby_action         => nil,
      :previous_state         => "up",
      :last_perf_capture_on   => nil,
      :registered             => nil,
      :busy                   => nil,
      :smart                  => nil,
      :memory_reserve         => 1024,
      :memory_reserve_expand  => nil,
      :memory_limit           => nil,
      :memory_shares          => nil,
      :memory_shares_level    => nil,
      :cpu_reserve            => nil,
      :cpu_reserve_expand     => nil,
      :cpu_limit              => nil,
      :cpu_shares             => nil,
      :cpu_shares_level       => nil,
      :cpu_affinity           => nil,
      :ems_created_on         => nil,
      :evm_owner_id           => nil,
      :linked_clone           => nil,
      :fault_tolerance        => nil,
      :type                   => "ManageIQ::Providers::Redhat::InfraManager::Vm",
      :ems_cluster_id         => @cluster.id,
      :retirement_warn        => nil,
      :retirement_last_warn   => nil,
      :vnc_port               => nil,
      :flavor_id              => nil,
      :availability_zone_id   => nil,
      :cloud                  => false,
      :retirement_state       => nil,
      :cloud_network_id       => nil,
      :cloud_subnet_id        => nil,
      :cloud_tenant_id        => nil,
      :publicly_available     => nil,
      :orchestration_stack_id => nil,
      :retirement_requester   => nil,
      :resource_group_id      => nil,
      :deprecated             => nil,
      :storage_profile_id     => nil
    )

    expect(vm.ext_management_system).to eq(@ems)
    expect(vm.ems_cluster).to eq(@cluster)
    expect(vm.storage).to eq(storage)
  end

  def assert_vm_rels(vm, hardware, storage)
    expect(vm.snapshots.size).to eq(1)
    snapshot = vm.snapshots.first
    expect(snapshot).to have_attributes(
      :uid               => "768f1e7a-c517-4619-9d55-59e641bfd038",
      :parent_uid        => nil,
      :uid_ems           => "768f1e7a-c517-4619-9d55-59e641bfd038",
      :name              => "Active VM",
      :description       => "Active VM",
      :current           => 1,
      :total_size        => nil,
      :filename          => nil,
      :disks             => [],
      :parent_id         => nil,
      :vm_or_template_id => vm.id,
      :ems_ref           => nil
    )

    expect(vm.hardware).to eq(hardware)
    expect(vm.hardware).to have_attributes(
      :guest_os             => "other",
      :guest_os_full_name   => nil,
      :bios                 => nil,
      :cpu_cores_per_socket => 1,
      :cpu_total_cores      => 1,
      :cpu_sockets          => 1,
      :annotation           => nil,
      :memory_mb            => 1024,
      :config_version       => nil,
      :virtual_hw_version   => nil,
      :bios_location        => nil,
      :time_sync            => nil,
      :vm_or_template_id    => vm.id,
      :host_id              => nil,
      :cpu_speed            => nil,
      :cpu_type             => nil,
      :size_on_disk         => nil,
      :manufacturer         => "",
      :model                => "",
      :number_of_nics       => nil,
      :cpu_usage            => nil,
      :memory_usage         => nil,
      :vmotion_enabled      => nil,
      :disk_free_space      => nil,
      :disk_capacity        => nil,
      :memory_console       => nil,
      :bitness              => nil,
      :virtualization_type  => nil,
      :root_device_type     => nil,
      :computer_system_id   => nil,
      :disk_size_minimum    => nil,
      :memory_mb_minimum    => nil
    )

    expect(vm.hardware.disks.size).to eq(1)
    disk = vm.hardware.disks.first
    expect(disk.storage).to eq(storage)
    expect(disk).to have_attributes(
      :device_name        => "GlanceDisk-73786f4",
      :device_type        => "disk",
      :location           => "0",
      :filename           => "da123bb9-095a-4933-95f2-8032dfa332e1",
      :hardware_id        => hardware.id,
      :mode               => "persistent",
      :controller_type    => "virtio",
      :size               => 41.megabyte,
      :free_space         => nil,
      :size_on_disk       => 25.megabyte,
      :present            => true,
      :start_connected    => true,
      :auto_detect        => nil,
      :disk_type          => "thin",
      :storage_id         => storage.id,
      :backing_id         => nil,
      :backing_type       => nil,
      :storage_profile_id => nil,
      :bootable           => false
    )

    expect(vm.hardware.guest_devices.size).to eq(1)
    guest_device = vm.hardware.guest_devices.first
    expect(guest_device).to have_attributes(
      :device_name       => "nic1",
      :device_type       => "ethernet",
      :location          => nil,
      :filename          => nil,
      :hardware_id       => hardware.id,
      :mode              => nil,
      :controller_type   => "ethernet",
      :size              => nil,
      :free_space        => nil,
      :size_on_disk      => nil,
      :address           => "00:1a:4a:16:01:52",
      :switch_id         => nil,
      :lan_id            => nil,
      :model             => nil,
      :iscsi_name        => nil,
      :iscsi_alias       => nil,
      :present           => true,
      :start_connected   => true,
      :auto_detect       => nil,
      :uid_ems           => "6409858a-e1a1-4049-bef2-22a438442420",
      :chap_auth_enabled => nil
    )

    expect(vm.operating_system).not_to be_nil
    expect(vm.operating_system).to have_attributes(
      :name                  => nil,
      :product_name          => "other",
      :version               => nil,
      :build_number          => nil,
      :system_root           => nil,
      :distribution          => nil,
      :product_type          => nil,
      :service_pack          => nil,
      :productid             => nil,
      :vm_or_template_id     => vm.id,
      :host_id               => nil,
      :bitness               => nil,
      :product_key           => nil,
      :pw_hist               => nil,
      :max_pw_age            => nil,
      :min_pw_age            => nil,
      :min_pw_len            => nil,
      :pw_complex            => nil,
      :pw_encrypt            => nil,
      :lockout_threshold     => nil,
      :lockout_duration      => nil,
      :reset_lockout_counter => nil,
      :system_type           => "desktop",
      :computer_system_id    => nil,
      :kernel_version        => nil
    )
  end

  def assert_cluster(vm)
    @cluster.reload
    expect(@cluster).to have_attributes(
      :ems_ref                 => "/api/clusters/00000002-0002-0002-0002-0000000001e9",
      :uid_ems                 => "00000002-0002-0002-0002-0000000001e9",
      :name                    => "Default",
      :ha_enabled              => nil,
      :ha_admit_control        => nil,
      :ha_max_failures         => nil,
      :drs_enabled             => nil,
      :drs_automation_level    => nil,
      :drs_migration_threshold => nil,
      :last_perf_capture_on    => nil,
      :effective_cpu           => nil,
      :effective_memory        => nil,
      :type                    => nil
    )

    rp = vm.parent_resource_pool
    expect(@cluster.default_resource_pool).to eq(rp)
    expect(rp).to have_attributes(
      :ems_ref               => nil,
      :ems_ref_obj           => nil,
      :uid_ems               => "00000002-0002-0002-0002-0000000001e9_respool",
      :name                  => "Default for Cluster Default",
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
      :is_default            => true,
      :vapp                  => nil
    )

    expect(vm.parent_datacenter).to have_attributes(
      :name    => "Default",
      :ems_ref => "/api/datacenters/00000001-0001-0001-0001-0000000002c0",
      :uid_ems => "00000001-0001-0001-0001-0000000002c0",
      :type    => "Datacenter",
      :hidden  => nil
    )
  end

  def assert_storage(storage, vm)
    storage.reload

    expect(vm.storage).to eq(storage)
    expect(storage).to have_attributes(
      :name                          => "data",
      :store_type                    => "NFS",
      :total_space                   => 922.gigabyte,
      :free_space                    => 791.gigabyte,
      :multiplehostaccess            => 1,
      :location                      => "192.168.1.106:/home/pkliczewski/export/hosted",
      :last_scan_on                  => nil,
      :uncommitted                   => 908.gigabyte,
      :last_perf_capture_on          => nil,
      :directory_hierarchy_supported => nil,
      :thin_provisioning_supported   => nil,
      :raw_disk_mappings_supported   => nil,
      :master                        => true,
      :ems_ref                       => "/api/storagedomains/ee745353-c069-4de8-8d76-ec2e155e2ca0",
      :storage_domain_type           => "data"
    )
  end
end
