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
    before do
      @options = {:vm_memory        => '1024',
                  :number_of_cpus   => '8',
                  :cores_per_socket => '2',
                  :disk_add         => [{  "disk_size_in_mb"  => "33",
                                           "persistent"       => true,
                                           "thin_provisioned" => true,
                                           "dependent"        => true,
                                           "bootable"         => false
                                        }],
                  :disk_remove      => [{  "disk_name"      => "2520b46a-799b-472d-89ce-d47f5b65ee5e",
                                           "delete_backing" => false
                                        }]
      }
      @vm = FactoryBot.create(:vm_redhat, :hardware => FactoryBot.create(:hardware), :storage => storage)
    end
    subject { @vm.build_config_spec(@options) }

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
