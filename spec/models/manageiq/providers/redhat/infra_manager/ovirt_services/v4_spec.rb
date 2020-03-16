describe ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4 do
  describe "#advertised_images" do
    let(:ems) { FactoryBot.create(:ems_redhat_with_authentication) }
    let(:vm) { FactoryBot.create(:vm_redhat, :ext_management_system => ems) }
    let(:ems_service) { instance_double(OvirtSDK4::Connection) }
    let(:system_service) { instance_double(OvirtSDK4::SystemService) }
    let(:data_centers_service) { instance_double(OvirtSDK4::DataCentersService) }
    let(:data_center_up) { OvirtSDK4::DataCenter.new(:status => OvirtSDK4::DataCenterStatus::UP) }
    let(:data_center_down) { OvirtSDK4::DataCenter.new(:status => OvirtSDK4::DataCenterStatus::MAINTENANCE) }
    let(:active_data_centers) { [data_center_up] }
    let(:storage_domain_list_1) { instance_double(OvirtSDK4::List) }
    let(:storage_domains) { [storage_domain_data, storage_domain_iso_down, storage_domain_iso_up] }
    let(:storage_domain_data) { OvirtSDK4::StorageDomain.new(:status => nil, :type => "data") }
    let(:storage_domain_iso_down) { OvirtSDK4::StorageDomain.new(:status => "maintenance", :type => "iso") }
    let(:storage_domain_iso_up) { OvirtSDK4::StorageDomain.new(:status => "active", :type => "iso", :id => "iso_sd_id") }
    let(:storage_domains_service) { instance_double(OvirtSDK4::StorageDomainsService) }
    let(:storage_domain_iso_up_service) { instance_double(OvirtSDK4::StorageDomainService) }
    let(:files_service) { instance_double(OvirtSDK4::FilesService) }
    let(:iso_images) { [double("iso1", :name => "iso_1"), double("iso2", :name => "iso_2")] }
    let(:query) { { :search => "status=#{OvirtSDK4::DataCenterStatus::UP}" } }

    before do
      allow(ems).to receive(:with_provider_connection).and_yield(ems_service)
      allow(ems_service).to receive(:system_service).and_return(system_service)
      allow(system_service).to receive(:data_centers_service).and_return(data_centers_service)
      allow(data_centers_service).to receive(:list).with(:query => query).and_return(active_data_centers)
      allow(data_center_up).to receive(:storage_domains).and_return(storage_domain_list_1)
      allow(ems_service).to receive(:follow_link).with(storage_domain_list_1).and_return(storage_domains)
      allow(system_service).to receive(:storage_domains_service).and_return(storage_domains_service)
      allow(storage_domains_service).to receive(:storage_domain_service).with(storage_domain_iso_up.id).and_return(storage_domain_iso_up_service)
      allow(storage_domain_iso_up_service).to receive(:files_service).and_return(files_service)
      allow(files_service).to receive(:list).and_return(iso_images)
    end

    subject(:advertised_images) do
      described_class.new(:ems => ems).advertised_images
    end

    context "there is a an active data-center" do
      context "there are iso domains attached to the data-center" do
        context "there are active iso domains" do
          it 'returns iso images from an active domain' do
            expect(advertised_images).to match_array(%w[iso_1 iso_2])
          end
        end

        context "there are no active iso domains" do
          let(:storage_domains) { [storage_domain_data, storage_domain_iso_down] }

          it 'returns an empty array' do
            expect(advertised_images).to match_array([])
          end
        end
      end

      context "there are no iso domains attached to the data-center" do
        let(:storage_domains) { [storage_domain_data] }

        it 'returns an empty array' do
          expect(advertised_images).to match_array([])
        end
      end
    end

    context "there are no active data-centers" do
      let(:active_data_centers) { [] }

      it 'returns an empty array' do
        expect(advertised_images).to match_array([])
      end
    end
  end

  describe "#vm_reconfigure" do
    let(:vm_proxy) { double("OvirtSDK4::Vm.new", :name => "vm_name_1", :next_run_configuration_exists => false) }

    let(:zone) do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end

    let(:ems) do
      FactoryBot.create(:ems_redhat_with_authentication, :zone => zone)
    end

    let(:vm) do
      FactoryBot.create(:vm_redhat, :ext_management_system => ems).tap do |v|
        allow(v).to receive(:with_provider_object).and_yield(vm_service)
      end
    end

    let(:vm_service) do
      double("OvirtSDK4::Vm").tap do |s|
        allow(s).to receive(:get).and_return(vm_proxy)
      end
    end

    it 'cpu_topology' do
      cores_per_socket = 2
      num_of_sockets = 3

      spec = {
        "numCPUs"           => cores_per_socket * num_of_sockets,
        "numCoresPerSocket" => cores_per_socket
      }

      expect(vm_service).to receive(:update)
        .with(
          OvirtSDK4::Vm.new(
            :cpu => {
              :topology => {
                :cores   => cores_per_socket,
                :sockets => num_of_sockets
              }
            }
          ),
          :next_run => false
        )
      ems.vm_reconfigure(vm, :spec => spec)
    end

    context "both cpu and memory" do
      let(:future_cores_per_socket) { 1 }
      let(:future_sockets) { 1 }
      let(:future_memory) { 3.gigabytes }
      let(:max_memory) { 4.gigabytes }
      let(:guaranteed_memory) { 1.gigabytes }

      let(:new_vm_specs) do
        {
          'numCPUs'           => future_cores_per_socket * future_sockets,
          'numCoresPerSocket' => future_cores_per_socket,
          'memoryMB'          => future_memory / 1.megabytes
        }
      end

      let(:memory_policy) { double('memory_policy', :guaranteed => guaranteed_memory, :max => max_memory) }
      let(:vm_status) { OvirtSDK4::VmStatus::UP }

      before(:each) do
        allow(vm_proxy).to receive(:status).and_return(vm_status)
        allow(vm_proxy).to receive(:memory).and_return(4.gigabytes)
        allow(vm_proxy).to receive(:memory_policy).and_return(memory_policy)
        allow(ems).to receive(:version_at_least?).with('4.1').and_return(true)
      end

      it "vm without pending next_run" do
        expect(vm_proxy).to receive(:next_run_configuration_exists).and_return(false)
        expect(vm_service).to receive(:update)
          .with(
            OvirtSDK4::Vm.new(
              :memory        => future_memory,
              :memory_policy => {
                :guaranteed => guaranteed_memory,
                :max        => max_memory
              },
              :cpu           => {
                :topology => {
                  :cores   => future_cores_per_socket,
                  :sockets => future_sockets
                }
              }
            ),
            :next_run => false
          )

        ems.vm_reconfigure(vm, :spec => new_vm_specs)
      end

      it "vm with pending next_run" do
        expect(vm_proxy).to receive(:next_run_configuration_exists).and_return(true)
        expect(vm_service).to receive(:update)
          .with(
            OvirtSDK4::Vm.new(
              :memory        => future_memory,
              :memory_policy => {
                :guaranteed => guaranteed_memory,
                :max        => max_memory
              },
              :cpu           => {
                :topology => {
                  :cores   => future_cores_per_socket,
                  :sockets => future_sockets
                }
              }
            ),
            :next_run => true
          )

        ems.vm_reconfigure(vm, :spec => new_vm_specs)
      end
    end

    describe 'add network adapters' do
      let(:connection) { double("OvirtSDK4::Connection") }
      let(:nics_service) { double('OvirtSDK4::VmNicsService') }

      before :each do
        allow(vm_service).to receive(:connection).and_return(connection)
        allow(vm_service).to receive(:nics_service).and_return(nics_service)
      end

      let :spec do
        {'networkAdapters' => {:add => [{:network         => 'oVirtA',
                                         :name            => 'nic2',
                                         :vnic_profile_id => 'ovirta_uid_ems'}]}}
      end

      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }

      it 'calls the add command with mandatory params' do
        expect(nics_service).to receive(:add).with(nic_with_mandatory_attrs(spec['networkAdapters'][:add].first))

        subject
      end

      context 'errors' do
        let(:error) { OvirtSDK4::Error.new }

        it 'already existing nic' do
          fault = OvirtSDK4::Fault.new(:reason => 'Operation Failed',
                                       :detail => '[Network interface name is already in use]')
          error.fault = fault
          error.code = 409

          expect(nics_service).to receive(:add).and_raise(error)
          expect($log).to receive(:error).with(/Error reconfiguring.*name is already in use/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error reconfiguring [#{spec['networkAdapters'][:add][0][:name]}]. #{error.fault.detail}")
        end

        it 'not existing profile id' do
          fault = OvirtSDK4::Fault.new(:reason => 'Operation Failed',
                                       :detail => '[Cannot add Interface. The specified VM network interface profile doesn\'t exist.]')
          error.fault = fault
          error.code = 400

          expect(nics_service).to receive(:add).and_raise(error)
          expect($log).to receive(:error).with(/Error reconfiguring.*network interface profile doesn't exist.\]/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error reconfiguring [#{spec['networkAdapters'][:add][0][:name]}]. #{error.fault.detail}")
        end
      end

      RSpec::Matchers.define :nic_with_mandatory_attrs do |attrs|
        match do |nic|
          res = nic.kind_of?(OvirtSDK4::Nic)
          res &&= (nic.name == attrs[:name])
          res &&= (nic.vnic_profile.id == attrs[:vnic_profile_id])
          res
        end
      end
    end

    describe 'edit network adapters' do
      let(:connection) { double("OvirtSDK4::Connection") }
      let(:nics_service) { double('OvirtSDK4::VmNicsService') }
      let(:nic_service) { double('OvirtSDk4::VmNicService') }

      before :each do
        allow(vm_service).to receive(:connection).and_return(connection)
        allow(vm_service).to receive(:nics_service).and_return(nics_service)
      end

      let :spec do
        {'networkAdapters' => {:edit => [{:network         => 'oVirtA',
                                          :name            => 'nic2',
                                          :vnic_profile_id => 'ovirta_uid_ems',
                                          :nic_id          => 'nic_uid_ems'}]}}
      end

      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }

      it 'calls the add command with mandatory params' do
        edit_spec = spec['networkAdapters'][:edit].first
        expect(nics_service).to receive(:nic_service).twice.with(edit_spec[:nic_id]).and_return(nic_service)
        expect(nic_service).to receive(:deactivate)
        expect(nic_service).to receive(:update).with(:name         => edit_spec[:name],
                                                     :vnic_profile => {:id => edit_spec[:vnic_profile_id]})
        expect(nic_service).to receive(:activate)

        subject
      end

      context 'errors' do
        it 'not existing nic' do
          expect(nics_service).to receive(:nic_service).and_raise(OvirtSDK4::NotFoundError)
          expect($log).to receive(:error).with(/Error reconfiguring.*NIC not found/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error reconfiguring [#{spec['networkAdapters'][:edit][0][:name]}]. NIC not found")
        end

        it 'not existing profile id' do
          fault = OvirtSDK4::Fault.new(:reason => "Operation Failed",
                                       :detail => "[Cannot edit Interface. The specified VM network interface profile doesn't exist.]")
          error = OvirtSDK4::Error.new fault.detail
          error.code = 400
          error.fault = fault

          expect(nics_service).to receive(:nic_service).and_raise(error)
          expect($log).to receive(:error).with(/Error reconfiguring.*network interface profile doesn't exist.\]/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error reconfiguring [#{spec['networkAdapters'][:edit][0][:name]}]. #{error.fault.detail}")
        end
      end
    end

    describe 'remove network adapters' do
      let(:connection) { double("OvirtSDK4::Connection") }
      let(:nics_service) { double('OvirtSDK4::VmNicsService') }
      let(:nic_service) { double('OvirtSDk4::VmNicService') }

      before :each do
        allow(vm_service).to receive(:connection).and_return(connection)
        allow(vm_service).to receive(:nics_service).and_return(nics_service)
      end

      let :spec do
        {'networkAdapters' => {:remove => [{:network     => 'oVirtA',
                                            :name        => 'nic2',
                                            :mac_address => '56:6f:85:ae:00:00',
                                            :nic_id      => 'nic_uid_ems'}]}}
      end

      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }

      it 'calls the remove command with mandatory params' do
        remove_spec = spec['networkAdapters'][:remove].first
        expect(nics_service).to receive(:nic_service).with(remove_spec[:nic_id]).and_return(nic_service)
        expect(nic_service).to receive(:deactivate)
        expect(nic_service).to receive(:remove)

        subject
      end

      context 'errors' do
        it 'not existing nic' do
          expect(nics_service).to receive(:nic_service).and_raise(OvirtSDK4::NotFoundError)
          expect($log).to receive(:error).with(/Error reconfiguring.*NIC not found |.*/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error reconfiguring [#{spec['networkAdapters'][:remove][0][:name]}]. NIC not found")
        end

        it 'generic error while removing' do
          fault = OvirtSDK4::Fault.new(:reason => "Operation Failed",
                                       :detail => "[generic failure]")
          error = OvirtSDK4::Error.new fault.detail
          error.fault = fault

          remove_spec = spec['networkAdapters'][:remove].first
          expect(nics_service).to receive(:nic_service).with(remove_spec[:nic_id]).and_return(nic_service)
          expect(nic_service).to receive(:deactivate)
          expect(nic_service).to receive(:remove).and_raise(error)
          expect($log).to receive(:error).with(/Error reconfiguring.*generic failure\]/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error reconfiguring [#{spec['networkAdapters'][:remove][0][:name]}]. #{error.fault.detail}")
        end
      end
    end

    describe "edit disk" do
      let(:connection) { double("OvirtSDK4::Connection") }
      let(:disk_attachments_service) { double('OvirtSDK4::DiskAttachmentsService') }
      let(:disk_attachment_service) { double('OvirtSDK4::DiskAttachmentService') }

      before :each do
        allow(vm_service).to receive(:connection).and_return(connection)
        allow(vm_service).to receive(:disk_attachments_service).and_return(disk_attachments_service)
      end

      let(:spec) do
        {'disksEdit' => [{:disk_name       => '36b02b75-fcbd-42c1-818f-82ec90d4780b',
                          :disk_size_in_mb => 8192}]}
      end

      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }

      it 'calls the update command with mandatory parameters' do
        disk_spec = spec['disksEdit'].first
        expect(disk_attachments_service).to receive(:attachment_service).with(disk_spec[:disk_name]).and_return(disk_attachment_service)
        expect(disk_attachment_service).to receive(:update).with(hash_including(:disk => {:provisioned_size => disk_spec[:disk_size_in_mb].megabytes}))

        subject
      end

      context 'errors' do
        before :each do
          allow(disk_attachments_service).to receive(:attachment_service).with(kind_of(String)).and_return(disk_attachment_service)
        end

        it 'disk with specified name not found' do
          expect(disk_attachment_service).to receive(:update).and_raise(OvirtSDK4::NotFoundError)
          expect($log).to receive(:error).with(/No disk with the id.*is attached to the vm/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "No disk with the id [#{spec['disksEdit'].first[:disk_name]}] is attached to the vm")
        end

        it 'new disk size smaller than the current one' do
          fault = OvirtSDK4::Fault.new(:reason => "Operation Failed",
                                       :detail => "[Cannot edit Virtual Disk. New disk size must be larger than the current disk size.]")
          error = OvirtSDK4::Error.new fault.detail
          error.fault = fault

          expect(disk_attachment_service).to receive(:update).and_raise(error)
          expect($log).to receive(:error).with(/Error resizing disk with the id.*current disk size\.\]/)

          expect { subject }.to raise_error(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Error,
                                            "Error resizing disk with the id [#{spec['disksEdit'].first[:disk_name]}]. #{error.fault.detail}")
        end
      end
    end

    describe "remove disk" do
      let(:disk_1) { double("OvirtSDK4::Disk", :id => 'disk_id1', :name => 'disk1') }
      let(:disk_2) { double("OvirtSDK4::Disk", :id => 'disk_id2', :name => 'disk2') }
      let(:disk_attachments_service) { double("OvirtSDK4::DiskAttachmentsService") }
      let(:disk_attachment_service_1) { double("OvirtSDK4::DiskAttachmentService") }
      let(:connection) { double("OvirtSDK4::Connection") }

      before do
        allow(vm_service).to receive(:disk_attachments_service).and_return(disk_attachments_service)
        allow(vm_service).to receive(:connection).and_return(connection)
        allow(disk_attachments_service).to receive(:attachment_service).with(disk_1.id).and_return(disk_attachment_service_1)
        allow(disk_attachments_service).to receive(:attachment_service).with(disk_2.id).and_raise(OvirtSDK4::NotFoundError)
      end
      let(:delete_backing) { true }
      let(:spec) { { 'disksRemove' => [{ 'disk_name' => disk_1.id, 'delete_backing' => delete_backing }] } }
      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }
      context 'delete backing' do
        it 'sends a remove command to the appropriate disk attachment' do
          expect(disk_attachment_service_1).to receive(:remove).with(:detach_only => false)
          subject
        end
      end

      context 'detach without removing disk' do
        let(:delete_backing) { false }
        it 'sends a remove command to the appropriate disk attachment' do
          expect(disk_attachment_service_1).to receive(:remove).with(:detach_only => true)
          subject
        end
      end

      context 'disk missing' do
        let(:spec) { { 'disksRemove' => [{ 'disk_name' => disk_2.id, 'delete_backing' => delete_backing }] } }
        it 'raises an error with the vm and disk name' do
          expect { subject }.to raise_error("no disk with the id #{disk_2.id} is attached to the vm: vm_name_1")
        end

        it 'raises an error with the vm and disk name in case of generic error' do
          allow(disk_attachments_service).to receive(:attachment_service).with(disk_2.id).and_raise(OvirtSDK4::Error)
          expect { subject }.to raise_error("Failed to detach disk with the id #{disk_2.id} from the vm: vm_name_1, check that it exists")
        end
      end
    end

    describe "memory" do
      before do
        @memory_policy = double("memory_policy")
        allow(@memory_policy).to receive(:guaranteed).and_return(2.gigabytes)
        allow(vm_proxy).to receive(:status).and_return(vm_status)
        allow(vm_proxy).to receive(:memory).and_return(0)
        allow(vm_proxy).to receive(:memory_policy).and_return(@memory_policy)
        allow(vm_proxy).to receive(:name).and_return("vm_name")
        @memory_spec = { :memory => memory, :memory_policy => { :guaranteed => guaranteed } }
      end
      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }
      let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte } }
      let(:memory) { 8.gigabytes }
      let(:guaranteed) { 2.gigabytes }
      context "vm is up" do
        let(:vm_status) { OvirtSDK4::VmStatus::UP }
        it 'updates configuration' do
          expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec), :next_run => false)
          reconfigure_vm
        end

        context "memory is bigger than vms memory should be rounded up by 256" do
          let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte + 1 } }
          let(:memory) { 8.gigabytes + 256.megabytes }
          it 'adjusts the increased memory to the next 256 MiB multiple if the VM is up' do
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec), :next_run => false)
            reconfigure_vm
          end
        end

        context "memory is less than vms memory should be rounded up" do
          let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte - 1 } }
          it 'adjusts reduced memory to the next 256 MiB multiple if the VM is up' do
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec), :next_run => false)
            reconfigure_vm
          end
        end

        context "guaranteed memory is bigger than vms" do
          let(:spec) { { 'memoryMB' => 1.gigabyte / 1.megabyte } }
          let(:memory) { 1.gigabyte }
          it 'adjusts the guaranteed memory if it is larger than the virtual memory' do
            mod_memory_spec = { :memory => memory, :memory_policy => { :guaranteed => 1.gigabyte } }
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(mod_memory_spec), :next_run => false)
            reconfigure_vm
          end
        end
      end

      context "vm is down" do
        let(:vm_status) { OvirtSDK4::VmStatus::DOWN }

        context "guaranteed memory is bigger than vms" do
          let(:spec) { { 'memoryMB' => 1.gigabyte / 1.megabyte } }
          let(:memory) { 1.gigabyte }
          it 'adjusts the guaranteed memory if it is larger than the virtual memory' do
            mod_memory_spec = { :memory => memory, :memory_policy => { :guaranteed => 1.gigabyte } }
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(mod_memory_spec), :next_run => false)
            reconfigure_vm
          end
        end
      end
    end

    describe "max memory" do
      before do
        @memory_policy = double("memory_policy")
        allow(@memory_policy).to receive(:guaranteed).and_return(2.gigabytes)
        allow(vm_proxy).to receive(:status).and_return(OvirtSDK4::VmStatus::DOWN)
        allow(vm_proxy).to receive(:memory).and_return(0)
        allow(vm_proxy).to receive(:memory_policy).and_return(@memory_policy)
        allow(vm_proxy).to receive(:name).and_return("vm_name")
      end

      subject(:reconfigure_vm) { ems.vm_reconfigure(vm, :spec => spec) }

      let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte } }
      let(:memory) { 8.gigabytes }
      let(:max) { 6.gigabytes }

      context "api version supports max" do
        before do
          allow(ems).to receive(:version_at_least?).with('4.1').and_return(true)
          @memory_spec = { :memory => memory, :memory_policy => { :guaranteed => 2.gigabyte, :max => max } }
        end

        context "memory limit is smaller than 1TB" do
          it "sets the max memory 4 times of the required limit" do
            allow(@memory_policy).to receive(:max).and_return(6.gigabytes)

            mod_memory_policy = { :guaranteed => 2.gigabyte, :max => 32.gigabytes }
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes, :memory_policy => mod_memory_policy), :next_run => false)
            reconfigure_vm
          end

          it "doesn't change the max if greater the max is greater than the limit" do
            allow(@memory_policy).to receive(:max).and_return(16.gigabytes)

            mod_memory_policy = { :guaranteed => 2.gigabyte, :max => 16.gigabytes }
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes, :memory_policy => mod_memory_policy), :next_run => false)
            reconfigure_vm
          end
        end

        context "memory limit is greater than 1TB" do
          let(:spec) { { 'memoryMB' => 2.terabytes / 1.megabyte } }

          it "sets the max memory as the limit" do
            allow(@memory_policy).to receive(:max).and_return(16.gigabytes)

            mod_memory_policy = { :guaranteed => 2.gigabyte, :max => 2.terabytes }
            expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 2.terabytes, :memory_policy => mod_memory_policy), :next_run => false)
            reconfigure_vm
          end
        end
      end

      context "api version doesn't support max" do
        it "doesn't pass the max in the request" do
          allow(ems).to receive(:version_at_least?).with('4.1').and_return(false)

          mod_memory_policy = { :guaranteed => 2.gigabyte }
          expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes, :memory_policy => mod_memory_policy), :next_run => false)
          reconfigure_vm
        end
      end
    end

    RSpec::Matchers.define :vm_with_properly_set_disk_attachments do |opts|
      sparsity = opts[:sparse]
      storage_domain_href = opts[:storage]
      disk_format = opts[:disk_format]
      match do |actual|
        actual.disk_attachments.inject(true) do |res, disk_attachment|
          res &&= (disk_attachment.disk.sparse == sparsity)
          res &&= all_storage_domains_match_href?(disk_attachment.disk, storage_domain_href) if storage_domain_href
          res &&= (disk_attachment.disk.name =~ /#{opts[:name]}_Disk\d/)
          res &&= (disk_attachment.disk.format == disk_format)
          res
        end
      end
    end

    RSpec::Matchers.define :disk_attachments_with_properly_set_attributes do |opts|
      sparsity = opts[:sparse]
      storage_domain_href = opts[:storage]
      disk_format = opts[:disk_format]
      match do |disk_attachment|
        res = true
        res &&= (disk_attachment.disk.sparse == sparsity)
        res &&= all_storage_domains_match_href?(disk_attachment.disk, storage_domain_href) if storage_domain_href
        res &&= (disk_attachment.disk.name =~ /#{opts[:name]}_Disk\d/)
        res &&= (disk_attachment.disk.format == disk_format)
        res &&= disk_attachment.disk.id.nil?
        res
      end
    end
    RSpec::Matchers.define :vm_with_disk_attachments_not_set do
      match { |actual| actual.disk_attachments.blank? }
    end

    def all_storage_domains_match_href?(disk, href)
      disk.storage_domains.inject(true) { |res, storage_domain| res && storage_domain.href == href }
    end

    context "#start_clone" do
      before do
        @source_template = double("template")
        storage_domain = OvirtSDK4::StorageDomain.new(:href => "/api/storagedomains/href")
        storage_domain_old = OvirtSDK4::StorageDomain.new(:href => "/api/storagedomains/href_old")
        disk = OvirtSDK4::Disk.new(:id => "disk_id1", :storage_domains => [storage_domain_old])
        disk2 = OvirtSDK4::Disk.new(:id => "disk_id2", :storage_domains => [storage_domain_old])
        @disk_attachments = [OvirtSDK4::DiskAttachment.new(:disk => disk), OvirtSDK4::DiskAttachment.new(:disk => disk2)]
        @sdk_template = OvirtSDK4::Template.new(:disk_attachments => @disk_attachments)
        @ems = FactoryBot.create(:ems_redhat_with_authentication)
        @ovirt_services = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4.new(:ems => @ems)
        connection = double(OvirtSDK4::Connection)
        template_service = OvirtSDK4::TemplateService
        cluster = OvirtSDK4::Cluster.new(:cluster => "/api/clusters/href")
        system_services = OvirtSDK4::SystemService
        @vms_service = double(OvirtSDK4::VmsService)
        allow(connection).to receive(:system_service).and_return(system_services)
        allow(system_services).to receive(:vms_service).and_return(@vms_service)
        rhevm_template = ManageIQ::Providers::Redhat::InfraManager::
          OvirtServices::V4::TemplateProxyDecorator.new(template_service, connection, @ovirt_services)
        allow(rhevm_template).to receive(:get).and_return(@sdk_template)
        allow(@ovirt_services).to receive(:cluster_from_href).with("/api/clusters/href", connection).and_return(cluster)
        allow(@ovirt_services).to receive(:storage_from_href).with("/api/storagedomains/href", connection).and_return(storage_domain)
        allow(@source_template).to receive(:with_provider_object).and_yield(rhevm_template)
        allow(connection).to receive(:follow_link).with(@sdk_template.disk_attachments).and_return(@disk_attachments)
        allow(@ovirt_services).to receive(:populate_phase_context)
        allow(rhevm_template).to receive(:blank_template_sdk_obj).and_return(OvirtSDK4::Template.new)
        @disks_service = double(OvirtSDK4::DisksService)
        @disk_service = double(OvirtSDK4::DiskService)
        allow(system_services).to receive(:disks_service).and_return(@disks_service)
        @disk1_service = double(OvirtSDK4::Disk, :get => disk)
        @disk2_service = double(OvirtSDK4::Disk, :get => disk2)
        allow(@disks_service).to receive(:disk_service).with(disk.id).and_return(@disk1_service)
        allow(@disks_service).to receive(:disk_service).with(disk2.id).and_return(@disk2_service)
        vm_service = double(OvirtSDK4::VmService, :disk_attachments_service => @sdk_template.disk_attachments)
        allow(@vms_service).to receive(:vm_service).and_return(vm_service)
      end

      context "clone_type is full" do
        let(:create_options) { { :sparse => true } }
        it "requests to clone the vm as independant and sets the disk attachments attributes" do
          opts = {:name => "provision_vm", :cluster => "/api/clusters/href", :clone_type => :full, :sparse => false, :storage => "/api/storagedomains/href", :disk_format => "cow"}
          expect(@vms_service).to receive(:add).with(vm_with_properly_set_disk_attachments(opts), :clone => true)
          @ovirt_services.start_clone(@source_template, opts, {})
        end
      end

      context "clone_type is skeletal" do
        let(:create_options) { { :sparse => true } }
        it "requests to clone the vm as independant and sets the disk attachments attributes" do
          opts = {:name => "provision_vm", :cluster => "/api/clusters/href", :clone_type => :skeletal, :sparse => false, :storage => "/api/storagedomains/href", :disk_format => "cow"}
          expect(@vms_service).to receive(:add).and_return(OvirtSDK4::Vm.new(:id => "new_vm_id"))
          expect(@sdk_template.disk_attachments).to receive(:add).with(disk_attachments_with_properly_set_attributes(opts))
          expect(@sdk_template.disk_attachments).to receive(:add).with(disk_attachments_with_properly_set_attributes(opts))
          @ovirt_services.start_clone(@source_template, opts, {})
        end
      end
    end
  end
end
