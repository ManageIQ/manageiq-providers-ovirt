describe ManageIQ::Providers::Redhat::InfraManager::Vm::Reconfigure do
  let(:ems) do
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    FactoryBot.create(:ems_redhat, :zone => zone)
  end
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

    context 'disk resize' do
      let(:disk1) { FactoryBot.create(:disk, :filename => '36b02b75-fcbd-42c1-818f-82ec90d4780b', :size => 10.gigabytes) }
      let(:disk2) { FactoryBot.create(:disk, :filename => 'd9ba0873-5d5e-464a-945d-132bccba49fd', :size => 3.gigabytes) }
      let(:hardware) { FactoryBot.create(:hardware, :disks => [disk1, disk2]) }

      let(:vm) do
        FactoryBot.create(:vm_redhat,
                          :ext_management_system => ems,
                          :hardware              => hardware)
      end

      let(:disk_size_in_mb) { '4096' }
      let(:disk_name) { 'd9ba0873-5d5e-464a-945d-132bccba49fd' }

      let(:options) do
        {
          :disk_resize => [{"disk_name"       => disk_name,
                            "disk_size_in_mb" => disk_size_in_mb}]
        }
      end

      subject { vm.build_config_spec(options)['disksEdit'] }

      it 'new disk size greater or equal than the current one' do
        expect(subject.first).to include(:disk_name => disk_name, :disk_size_in_mb => disk_size_in_mb.to_i)
      end

      context 'snapshots' do
        before(:each) { EvmSpecHelper.local_miq_server }

        it 'supported with one active snapshot' do
          FactoryBot.create(:snapshot, :vm_or_template => vm, :create_time => 1.minute.ago)

          expect(vm.supports_reconfigure_disksize?).to be true
        end

        it 'unsupported with snapshots other than the active one' do
          FactoryBot.create_list(:snapshot, 2, :vm_or_template => vm, :create_time => 1.minute.ago)

          expect(vm.supports_reconfigure_disksize?).to be false
        end
      end

      context 'not existing vm disk' do
        let(:disk_name) { 'not-existing-disk-name' }

        it 'raise an exception' do
          expect { subject }.to raise_error(MiqException::MiqVmError, /No disk with filename.*was found/)
        end
      end

      context 'new disk size smaller than the current one' do
        let(:disk_size_in_mb) { '2048' }

        it 'raise an exception' do
          expect { subject }.to raise_error(MiqException::MiqVmError, /New disk size must be larger than the current one/)
        end
      end
    end
  end
end
