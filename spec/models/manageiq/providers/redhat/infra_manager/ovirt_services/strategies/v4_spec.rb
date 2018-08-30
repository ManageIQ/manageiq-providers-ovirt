describe ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4 do
  describe "#advertised_images" do
    let(:ems) { FactoryGirl.create(:ems_redhat_with_authentication) }
    let(:vm) { FactoryGirl.create(:vm_redhat, :ext_management_system => ems) }
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
            expect(advertised_images).to match_array(%w(iso_1 iso_2))
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
    before do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems  = FactoryGirl.create(:ems_redhat_with_authentication, :zone => zone)
      @hw   = FactoryGirl.create(:hardware, :memory_mb => 1024, :cpu_sockets => 2, :cpu_cores_per_socket => 1)
      @vm   = FactoryGirl.create(:vm_redhat, :ext_management_system => @ems)
      @cores_per_socket = 2
      @num_of_sockets   = 3
      @vm_proxy = double("OvirtSDK4::Vm.new")
      @vm_service = double("OvirtSDK4::Vm")
      allow(@ems).to receive(:highest_supported_api_version).and_return(4)
      allow(@vm).to receive(:with_provider_object).and_yield(@vm_service)
      allow(@vm_service).to receive(:get).and_return(@vm_proxy)
    end

    it 'cpu_topology' do
      spec = {
        "numCPUs"           => @cores_per_socket * @num_of_sockets,
        "numCoresPerSocket" => @cores_per_socket
      }

      expect(@vm_service).to receive(:update)
        .with(OvirtSDK4::Vm.new(
                :cpu => {
                  :topology => {
                    :cores   => @cores_per_socket,
                    :sockets => @num_of_sockets
                  }
                }
        ))
      @ems.vm_reconfigure(@vm, :spec => spec)
    end

    describe "memory" do
      before do
        @memory_policy = double("memory_policy")
        allow(@memory_policy).to receive(:guaranteed).and_return(2.gigabytes)
        allow(@vm_proxy).to receive(:status).and_return(vm_status)
        allow(@vm_proxy).to receive(:memory).and_return(0)
        allow(@vm_proxy).to receive(:memory_policy).and_return(@memory_policy)
        allow(@vm_proxy).to receive(:name).and_return("vm_name")
        @memory_spec = { :memory => memory, :memory_policy => { :guaranteed => guaranteed } }

      end
      subject(:reconfigure_vm) { @ems.vm_reconfigure(@vm, :spec => spec) }
      let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte } }
      let(:memory) { 8.gigabytes }
      let(:guaranteed) { 2.gigabytes }
      context "vm is up" do
        let(:vm_status) { OvirtSDK4::VmStatus::UP }
        it 'updates the current and persistent configuration if the VM is up' do
          expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec), :next_run => true)
          expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes))
          reconfigure_vm
        end

        context "memory is bigger than vms memory should be rounded up by 256" do
          let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte + 1 } }
          let(:memory) { 8.gigabytes + 256.megabytes }
          it 'adjusts the increased memory to the next 256 MiB multiple if the VM is up' do
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec), :next_run => true)
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => memory))
            reconfigure_vm
          end
        end

        context "memory is less than vms memory should be rounded up" do
          let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte - 1 } }
          it 'adjusts reduced memory to the next 256 MiB multiple if the VM is up' do
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec), :next_run => true)
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => memory))
            reconfigure_vm
          end
        end

        context "guaranteed memory is bigger than vms" do
          let(:spec) { { 'memoryMB' => 1.gigabyte / 1.megabyte } }
          let(:memory) { 1.gigabyte }
          it 'adjusts the guaranteed memory if it is larger than the virtual memory if the VM is up' do
            mod_memory_spec = { :memory => memory, :memory_policy => { :guaranteed => 1.gigabyte } }
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(mod_memory_spec), :next_run => true)
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => memory))
            reconfigure_vm
          end
        end
      end

      context "vm is down" do
        let(:vm_status) { OvirtSDK4::VmStatus::DOWN }
        it 'updates only the persistent configuration when the VM is down' do
          expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(@memory_spec))
          reconfigure_vm
        end

        context "guaranteed memory is bigger than vms" do
          let(:spec) { { 'memoryMB' => 1.gigabyte / 1.megabyte } }
          let(:memory) { 1.gigabyte }
          it 'adjusts the guaranteed memory if it is larger than the virtual memory if the VM is up' do
            mod_memory_spec = { :memory => memory, :memory_policy => { :guaranteed => 1.gigabyte } }
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(mod_memory_spec))
            reconfigure_vm
          end
        end
      end
    end

    describe "max memory" do
      before do
        @memory_policy = double("memory_policy")
        allow(@memory_policy).to receive(:guaranteed).and_return(2.gigabytes)
        allow(@vm_proxy).to receive(:status).and_return(OvirtSDK4::VmStatus::DOWN)
        allow(@vm_proxy).to receive(:memory).and_return(0)
        allow(@vm_proxy).to receive(:memory_policy).and_return(@memory_policy)
        allow(@vm_proxy).to receive(:name).and_return("vm_name")
      end

      subject(:reconfigure_vm) { @ems.vm_reconfigure(@vm, :spec => spec) }

      let(:spec) { { 'memoryMB' => 8.gigabytes / 1.megabyte } }
      let(:memory) { 8.gigabytes }
      let(:max) { 6.gigabytes }

      context "api version supports max" do
        before do
          allow(@ems).to receive(:version_at_least?).with('4.1').and_return(true)
          @memory_spec = { :memory => memory, :memory_policy => { :guaranteed => 2.gigabyte, :max => max } }
        end

        context "memory limit is smaller than 1TB" do
          it "sets the max memory 4 times of the required limit" do
            allow(@memory_policy).to receive(:max).and_return(6.gigabytes)

            mod_memory_policy = { :guaranteed => 2.gigabyte, :max => 32.gigabytes }
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes, :memory_policy => mod_memory_policy))
            reconfigure_vm
          end

          it "doesn't change the max if greater the max is greater than the limit" do
            allow(@memory_policy).to receive(:max).and_return(16.gigabytes)

            mod_memory_policy = { :guaranteed => 2.gigabyte, :max => 16.gigabytes }
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes, :memory_policy => mod_memory_policy))
            reconfigure_vm
          end
        end

        context "memory limit is greater than 1TB" do
          let(:spec) { { 'memoryMB' => 2.terabytes / 1.megabyte } }

          it "sets the max memory as the limit" do
            allow(@memory_policy).to receive(:max).and_return(16.gigabytes)

            mod_memory_policy = { :guaranteed => 2.gigabyte, :max => 2.terabytes }
            expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 2.terabytes, :memory_policy => mod_memory_policy))
            reconfigure_vm
          end
        end
      end

      context "api version doesn't support max" do
        it "doesn't pass the max in the request" do
          allow(@ems).to receive(:version_at_least?).with('4.1').and_return(false)

          mod_memory_policy = { :guaranteed => 2.gigabyte }
          expect(@vm_service).to receive(:update).with(OvirtSDK4::Vm.new(:memory => 8.gigabytes, :memory_policy => mod_memory_policy))
          reconfigure_vm
        end
      end
    end

    RSpec::Matchers.define :vm_with_properly_set_disk_attachments do |opts|
      sparsity = opts[:sparse]
      storage_domain_href = opts[:storage]
      match do |actual|
        actual.disk_attachments.inject(true) do |res, disk_attachment|
          res &&= (disk_attachment.disk.sparse == sparsity)
          res &&= all_storage_domains_match_href?(disk_attachment.disk, storage_domain_href) if storage_domain_href
          res
        end
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
        disk = OvirtSDK4::Disk.new(:storage_domains => [storage_domain_old])
        disk2 = OvirtSDK4::Disk.new(:storage_domains => [storage_domain_old])
        @disk_attachments = [OvirtSDK4::DiskAttachment.new(:disk => disk), OvirtSDK4::DiskAttachment.new(:disk => disk2)]
        @sdk_template = OvirtSDK4::Template.new(:disk_attachments => @disk_attachments)
        @ems = FactoryGirl.create(:ems_redhat_with_authentication)
        @ovirt_services = ManageIQ::Providers::Redhat::InfraManager::
          OvirtServices::Strategies::V4.new(:ems => @ems)
        connection = double(OvirtSDK4::Connection)
        template_service = OvirtSDK4::TemplateService
        cluster = OvirtSDK4::Cluster.new(:cluster => "/api/clusters/href")
        system_services = OvirtSDK4::SystemService
        @vms_service = double(OvirtSDK4::VmsService)
        allow(connection).to receive(:system_service).and_return(system_services)
        allow(system_services).to receive(:vms_service).and_return(@vms_service)
        rhevm_template = ManageIQ::Providers::Redhat::InfraManager::
          OvirtServices::Strategies::V4::TemplateProxyDecorator.new(template_service, connection, @ovirt_services)
        allow(rhevm_template).to receive(:get).and_return(@sdk_template)
        allow(@ovirt_services).to receive(:cluster_from_href).with("/api/clusters/href", connection).and_return(cluster)
        allow(@ovirt_services).to receive(:storage_from_href).with("/api/storagedomains/href", connection).and_return(storage_domain)
        allow(@source_template).to receive(:with_provider_object).and_yield(rhevm_template)
        allow(connection).to receive(:follow_link).with(@sdk_template.disk_attachments).and_return(@disk_attachments)
        allow(@ovirt_services).to receive(:populate_phase_context)
      end

      context "clone_type is full" do
        let(:create_options) { { :sparse => true } }
        it "requests to clone the vm as independant and sets the disk attachments attributes" do
          opts = {:name => "provision_vm", :cluster => "/api/clusters/href", :clone_type => :full, :sparse => false, :storage => "/api/storagedomains/href"}
          expect(@vms_service).to receive(:add).with(vm_with_properly_set_disk_attachments(opts), :clone => true)
          @ovirt_services.start_clone(@source_template, opts, {})
        end
      end

      context "clone_type is thin" do
        it "requests to clone the vm as dependant and does not set the disk attachments attributes" do
          opts = {:name => "provision_vm", :cluster => "/api/clusters/href", :clone_type => :thin, :sparse => true, :storage => "/api/storagedomains/href"}
          expect(@vms_service).to receive(:add).with(vm_with_disk_attachments_not_set, :clone => false)
          @ovirt_services.start_clone(@source_template, opts, {})
        end
      end
    end
  end
end
