describe ManageIQ::Providers::Redhat::InfraManager::Vm::Reconfigure do
  let(:storage) { FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ") }
  let(:vm)      { FactoryBot.create(:vm_redhat, :storage => storage) }

  describe "#reconfigurable?" do
    let(:vm_active)   { FactoryBot.create(:vm_redhat, :storage => storage, :ext_management_system => ems) }
    let(:vm_retired)  { FactoryBot.create(:vm_redhat, :retired => true, :storage => storage, :ext_management_system => ems) }
    let(:vm_archived) { FactoryBot.create(:vm_redhat) }
    let(:ems)         { FactoryBot.create(:ext_management_system) }

    it 'returns true for active vm' do
      expect(vm_active.reconfigurable?).to be_truthy
    end

    it 'returns false for orphaned vm' do
      expect(vm.reconfigurable?).to be_falsey
    end

    it 'returns false for retired vm' do
      expect(vm_retired.reconfigurable?).to be_falsey
    end

    it 'returns false for archived vm' do
      expect(vm_archived.reconfigurable?).to be_falsey
    end
  end

  it "#max_total_vcpus" do
    expect(vm.max_total_vcpus).to eq(160)
  end

  it "#max_cpu_cores_per_socket" do
    expect(vm.max_cpu_cores_per_socket).to eq(16)
  end

  it "#max_vcpus" do
    expect(vm.max_vcpus).to eq(16)
  end

  it "#max_memory_mb" do
    expect(vm.max_memory_mb).to eq(2.terabyte / 1.megabyte)
  end

  context "#build_config_spec" do
    let :options do
      {
        :vm_memory        => '1024',
        :number_of_cpus   => '8',
        :cores_per_socket => '2',
        :disk_add         => [{"disk_size_in_mb"  => "33",
                               "persistent"       => true,
                               "thin_provisioned" => true,
                               "dependent"        => true,
                               "bootable"         => false}],
        :disk_remove      => [{"disk_name"      => "2520b46a-799b-472d-89ce-d47f5b65ee5e",
                               "delete_backing" => false}]
      }
    end

    let(:vm) { FactoryBot.create(:vm_redhat, :hardware => FactoryBot.create(:hardware), :storage => storage) }

    subject { vm.build_config_spec(options) }

    it "memoryMB" do
      expect(subject["memoryMB"]).to eq(1024)
    end

    it "numCPUs" do
      expect(subject["numCPUs"]).to eq(8)
    end

    it "numCoresPerSocket" do
      expect(subject["numCoresPerSocket"]).to eq(2)
    end

    it "disksAdd" do
      disks = subject["disksAdd"][:disks]
      expect(disks.size).to eq(1)
      disk_to_add = disks[0]
      expect(disk_to_add["disk_size_in_mb"]).to eq("33")
      expect(disk_to_add["thin_provisioned"]).to eq(true)
      expect(disk_to_add["bootable"]).to eq(false)
      expect(subject["disksAdd"][:storage]).to eq(storage)
    end

    it "disksRemove" do
      expect(subject["disksRemove"].size).to eq(1)
      expect(subject["disksRemove"][0]["disk_name"]).to eq("2520b46a-799b-472d-89ce-d47f5b65ee5e")
      expect(subject["disksRemove"][0]["delete_backing"]).to be_falsey
    end

    context 'network adapters spec' do
      let(:ems) { FactoryBot.create(:ems_redhat) }
      let!(:dc1) { FactoryBot.create(:datacenter_redhat, :name => 'dc1', :ems_ref => 'dc1-ems-ref', :ems_ref_type => 'Datacenter') }
      let!(:cluster1) { FactoryBot.create(:ems_cluster, :uid_ems => "uid_ems", :name => 'Cluster1') }
      let!(:host1) { FactoryBot.create(:host_redhat, :ext_management_system => ems, :ems_cluster => cluster1) }
      let!(:host2) { FactoryBot.create(:host_redhat, :ext_management_system => ems, :ems_cluster => cluster1) }
      let!(:distributed_virtual_switch) { FactoryBot.create(:distributed_virtual_switch_redhat, :ems_id => ems.id, :name => "network") }
      let!(:host_switch_1) { FactoryBot.create(:host_switch, :host => host1, :switch => distributed_virtual_switch) }
      let!(:host_switch_2) { FactoryBot.create(:host_switch, :host => host2, :switch => distributed_virtual_switch) }
      let!(:lan_mgmt) { FactoryBot.create(:lan, :name => 'ovirtmgmt', :switch => distributed_virtual_switch) }
      let(:nic1) { FactoryBot.create(:guest_device_nic, :lan => lan_mgmt, :device_name => 'nic1', :uid_ems => 'nic1_uid_ems') }
      let(:hardware) { FactoryBot.create(:hardware, :guest_devices => [nic1]) }
      let!(:vm) do
        FactoryBot.create(:vm_redhat,
                          :ext_management_system => ems,
                          :host                  => host1,
                          :storage               => storage,
                          :hardware              => hardware)
      end

      shared_examples_for 'nic not found' do
        subject { vm.build_config_spec(specs) }

        it 'no nic for the vm' do
          expect { subject }.to raise_error(MiqException::MiqVmError, /No NIC named.*was found/)
        end
      end

      shared_examples_for 'not available lan' do |network_name|
        subject { vm.build_config_spec(specs) }

        it 'no lan for hosts' do
          expect { subject }.to raise_error(MiqException::MiqVmError, /Network.*not available for the target/)
        end

        it 'no lan for vm host' do
          wrong_switch = FactoryBot.create(:distributed_virtual_switch_redhat, :ems_id => ems.id, :name => "wrong_network")
          FactoryBot.create(:lan,
                            :name    => network_name,
                            :uid_ems => "#{network_name}_uid_ems",
                            :switch  => wrong_switch)
          FactoryBot.create(:host_switch, :host => host2, :switch => wrong_switch)

          expect { subject }.to raise_error(MiqException::MiqVmError, /Network.*not available.* for the target/)
        end
      end

      let :edit_specs do
        {:network_adapter_edit => [{'network' => 'oVirtB', 'name' => 'nic1'}]}
      end

      let :add_specs do
        {:network_adapter_add => [{'network' => 'oVirtA', 'name' => 'to be determined'}]}
      end

      let :remove_specs do
        {:network_adapter_remove => [{'network' => {'name'      => 'nic1',
                                                    'vlan'      => 'ovirtmgmt',
                                                    'mac'       => '56:6f:85:ae:00:00',
                                                    '$$hashKey' => 'object:51'}}]}
      end

      let :options do
        {}.merge(edit_specs).merge(add_specs)
      end

      context 'available lan' do
        before :each do
          FactoryBot.create(:lan,
                            :name    => 'oVirtA',
                            :uid_ems => 'ovirta_uid_ems',
                            :switch  => distributed_virtual_switch)

          FactoryBot.create(:lan,
                            :name    => 'oVirtB',
                            :uid_ems => 'ovirtb_uid_ems',
                            :switch  => distributed_virtual_switch)
        end

        context 'edit network' do
          subject { vm.build_config_spec(edit_specs)['networkAdapters'][:edit].first }

          it { is_expected.to include(:network => 'oVirtB', :name => 'nic1', :vnic_profile_id => 'ovirtb_uid_ems', :nic_id => 'nic1_uid_ems') }
        end

        context 'add network' do
          subject { vm.build_config_spec(add_specs)['networkAdapters'][:add].first }

          it { is_expected.to include(:network => 'oVirtA', :name => 'nic2', :vnic_profile_id => 'ovirta_uid_ems') }
        end
      end

      context 'external lan' do
        let!(:dc2) { FactoryBot.create(:datacenter_redhat, :name => 'dc2', :ems_ref => 'dc2-ems-ref', :ems_ref_type => 'Datacenter') }
        let!(:external_distributed_virtual_switch) do
          FactoryBot.create(:external_distributed_virtual_switch_redhat,
                            :ems_id => ems.id,
                            :name   => 'ext_network').tap { |e| e.parent = dc1 }
        end

        let!(:ext_switch2) do
          FactoryBot.create(:external_distributed_virtual_switch_redhat,
                            :ems_id => ems.id,
                            :name   => 'ext_network').tap { |e| e.parent = dc2 }
        end

        let!(:ext_lan) do
          FactoryBot.create(:lan,
                            :name    => 'ext_lan',
                            :uid_ems => 'ext_net_uid_ems',
                            :switch  => external_distributed_virtual_switch)
        end

        let!(:ext_lan2) do
          FactoryBot.create(:lan,
                            :name    => 'ext_lan',
                            :uid_ems => 'ext_net_uid_ems',
                            :switch  => ext_switch2)
        end

        before :each do
          expect(vm).to receive(:parent_datacenter).and_return(dc1)
        end

        context 'edit network' do
          subject { vm.build_config_spec(options)['networkAdapters'][:edit].first }

          let :options do
            {:network_adapter_edit => [{'network' => 'ext_lan/ext_network', 'name' => 'nic1'}]}
          end

          it { is_expected.to include(:network => 'ext_lan/ext_network', :name => 'nic1', :vnic_profile_id => 'ext_net_uid_ems', :nic_id => 'nic1_uid_ems') }
        end

        context 'add network' do
          subject { vm.build_config_spec(options)['networkAdapters'][:add].first }

          let :options do
            {:network_adapter_add => [{'network' => 'ext_lan/ext_network', 'name' => 'nic1'}]}
          end

          it { is_expected.to include(:network => 'ext_lan/ext_network', :name => 'nic2', :vnic_profile_id => 'ext_net_uid_ems') }
        end
      end

      context 'remove network' do
        subject { vm.build_config_spec(remove_specs)['networkAdapters'][:remove].first }

        it { is_expected.to include(:network => 'ovirtmgmt', :name => 'nic1', :mac_address => '56:6f:85:ae:00:00', :nic_id => nic1.uid_ems) }
      end

      context 'edit lan errors' do
        it_behaves_like 'not available lan', 'oVirtA' do
          let(:specs) { edit_specs }
        end
      end

      context 'add lan errors' do
        it_behaves_like 'not available lan', 'oVirtA' do
          let(:specs) { add_specs }
        end
      end

      context 'edit nic errors' do
        it_behaves_like 'nic not found' do
          let(:specs) do
            {:network_adapter_edit => [{'network' => 'oVirtB',
                                        'name'    => 'not_existing_nic'}]}
          end
        end
      end

      context 'add nic errors' do
        it_behaves_like 'nic not found' do
          let(:specs) do
            {:network_adapter_remove => [{'network' => {'name'      => 'not_existing_nic',
                                                        'vlan'      => 'ovirtmgmt',
                                                        'mac'       => '56:6f:85:ae:00:00',
                                                        '$$hashKey' => 'object:51'}}]}
          end
        end
      end
    end
  end

  describe '#suggest_nic_name' do
    subject { vm.suggest_nic_name(nics) }

    context 'no nics' do
      let(:nics) { %w[] }

      it { is_expected.to eq('nic1') }
    end

    context 'one nic' do
      let(:nics) { ['nic1'] }

      it { is_expected.to eq('nic2') }
    end

    context 'more nics' do
      let(:nics) { %w[nic1 nic20 nic10 nic2] }

      it { is_expected.to eq('nic21') }
    end

    context 'only nics with non standard names' do
      let(:nics) { %w[ext3 lo10] }

      it { is_expected.to eq('nic1') }
    end

    context 'nics with standard and non standard names' do
      let(:nics) { %w[nic14 ext3 lo10 nic2] }

      it { is_expected.to eq('nic15') }
    end
  end

  describe 'available_vlans' do
    let(:ems) { FactoryBot.create(:ems_redhat) }
    let!(:dc1) { FactoryBot.create(:datacenter_redhat, :name => 'dc1', :ems_ref => 'dc1-ems-ref', :ems_ref_type => 'Datacenter') }
    let!(:cluster) { FactoryBot.create(:ems_cluster, :uid_ems => "uid_ems", :name => 'cluster') }
    let!(:host1) { FactoryBot.create(:host_redhat, :ext_management_system => ems, :ems_cluster => cluster) }
    let!(:host2) { FactoryBot.create(:host_redhat, :ext_management_system => ems, :ems_cluster => cluster) }
    let!(:dist_switch) { FactoryBot.create(:distributed_virtual_switch_redhat, :ems_id => ems.id, :name => "network") }
    let!(:switch1) { FactoryBot.create(:distributed_virtual_switch_redhat, :ems_id => ems.id, :name => "network1") }
    let!(:switch2) { FactoryBot.create(:distributed_virtual_switch_redhat, :ems_id => ems.id, :name => "network2") }
    let!(:host_dist_switch1) { FactoryBot.create(:host_switch, :host => host1, :switch => dist_switch) }
    let!(:host_dist_switch2) { FactoryBot.create(:host_switch, :host => host2, :switch => dist_switch) }
    let!(:host_switch1) { FactoryBot.create(:host_switch, :host => host1, :switch => switch1) }
    let!(:host_switch2) { FactoryBot.create(:host_switch, :host => host2, :switch => switch2) }
    let!(:lan_mgmt) { FactoryBot.create(:lan, :name => 'ovirtmgmt', :switch => dist_switch) }
    let!(:vm) { FactoryBot.create(:vm_redhat, :ext_management_system => ems, :host => host1, :storage => storage) }

    context 'host vlans' do
      let!(:lan_A) { FactoryBot.create(:lan, :name => 'lanA', :switch => switch1) }
      let!(:lan_B) { FactoryBot.create(:lan, :name => 'lanB', :switch => switch2) }

      before :each do
        expect(vm).to receive(:parent_datacenter).and_return(dc1)
      end

      it 'only vlans related to vm host' do
        vlans = vm.available_vlans

        expect(vlans.count).to eq(2)
        expect(vlans).to match_array([lan_mgmt.name, lan_A.name])
      end

      context 'with external lans' do
        let!(:ext_dist_switch) do
          FactoryBot.create(:external_distributed_virtual_switch_redhat,
                            :ems_id => ems.id,
                            :name   => 'ext_network').tap { |e| e.parent = dc1 }
        end

        let!(:ext_lan) do
          FactoryBot.create(:lan,
                            :name    => 'ext_lan',
                            :uid_ems => 'ext_net_uid_ems',
                            :switch  => ext_dist_switch)
        end

        it 'host and external vlans' do
          vlans = vm.available_vlans

          expect(vlans.count).to eq(3)
          expect(vlans).to match_array([lan_mgmt.name, lan_A.name, "#{ext_lan.name}/#{ext_dist_switch.name}"])
        end

        context 'more datacenters with same external networks' do
          let!(:dc2) { FactoryBot.create(:datacenter_redhat, :name => 'dc2', :ems_ref => 'dc2-ems-ref', :ems_ref_type => 'Datacenter') }
          let!(:ext_dist_switch2) do
            FactoryBot.create(:external_distributed_virtual_switch_redhat,
                              :ems_id => ems.id,
                              :name   => 'ext_network').tap { |e| e.parent = dc2 }
          end

          let!(:ext_lan2) do
            FactoryBot.create(:lan,
                              :name    => 'ext_lan',
                              :uid_ems => 'ext_net_uid_ems',
                              :switch  => ext_dist_switch2)
          end

          it 'external vlans only for vm datacenter' do
            vlans = vm.available_vlans

            expect(vlans.count).to eq(3)
            expect(vlans).to match_array([lan_mgmt.name, lan_A.name, "#{ext_lan.name}/#{ext_dist_switch.name}"])
          end
        end
      end
    end
  end
end
