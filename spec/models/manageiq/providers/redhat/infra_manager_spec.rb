describe ManageIQ::Providers::Redhat::InfraManager do
  it ".ems_type" do
    expect(described_class.ems_type).to eq('rhevm')
  end

  it ".description" do
    expect(described_class.description).to eq('Red Hat Virtualization')
  end

  describe ".metrics_collector_queue_name" do
    it "returns the correct queue name" do
      worker_queue = ManageIQ::Providers::Redhat::InfraManager::MetricsCollectorWorker.default_queue_name
      expect(described_class.metrics_collector_queue_name).to eq(worker_queue)
    end
  end

  describe "rhevm_metrics_connect_options" do
    let(:ems) { FactoryGirl.create(:ems_redhat, :hostname => "some.thing.tld") }

    it "rhevm_metrics_connect_options fetches configuration and allows overrides" do
      expect(ems.rhevm_metrics_connect_options[:host]).to eq("some.thing.tld")
      expect(ems.rhevm_metrics_connect_options(:hostname => "different.tld")[:host])
        .to eq("different.tld")
    end

    it "rhevm_metrics_connect_options fetches the default database name" do
      expect(ems.rhevm_metrics_connect_options[:database])
        .to eq(ems.class.default_history_database_name)
    end

    context "non default metrics database name" do
      let(:ems) do
        FactoryGirl.create(:ems_redhat,
                           :hostname                  => "some.thing.tld",
                           :connection_configurations => [{:endpoint => {:role => :metrics,
                                                                         :path => "some.database"}}])
      end

      it "fetches the set database name" do
        expect(ems.rhevm_metrics_connect_options[:database]).to eq("some.database")
      end
    end
  end

  context "#vm_reconfigure" do
    context "version 4" do
      context "#vm_reconfigure" do
        before do
          _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
          @ems  = FactoryGirl.create(:ems_redhat_with_authentication, :zone => zone)
          @vm   = FactoryGirl.create(:vm_redhat, :ext_management_system => @ems)

          @rhevm_vm_attrs = double('rhevm_vm_attrs')
          allow(@ems).to receive(:highest_supported_api_version).and_return(4)
          stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => use_ovirt_engine_sdk } })
          @v4_strategy_instance = instance_double(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4)
          allow(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4)
            .to receive(:new)
            .and_return(@v4_strategy_instance)
        end

        context "use_ovirt_engine_sdk is set to true" do
          let(:use_ovirt_engine_sdk) { true }
          it 'sends vm_reconfigure to the right ovirt_services' do
            expect(@v4_strategy_instance).to receive(:vm_reconfigure).with(@vm, {})
            @ems.vm_reconfigure(@vm)
          end
        end

        context "use_ovirt_engine_sdk is set to false" do
          let(:use_ovirt_engine_sdk) { false }
          it 'sends vm_reconfigure to the right ovirt_services' do
            expect(@v4_strategy_instance).to receive(:vm_reconfigure).with(@vm, {})
            @ems.vm_reconfigure(@vm)
          end
        end
      end
    end

    context "version 3" do
      before do
        _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
        @ems  = FactoryGirl.create(:ems_redhat_with_authentication, :zone => zone)
        @hw   = FactoryGirl.create(:hardware, :memory_mb => 1024, :cpu_sockets => 2, :cpu_cores_per_socket => 1)
        @vm   = FactoryGirl.create(:vm_redhat, :ext_management_system => @ems)

        @cores_per_socket = 2
        @num_of_sockets   = 3

        @rhevm_vm_attrs = double('rhevm_vm_attrs')
        stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => false } })
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:name).and_return('myvm')
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:memory).and_return(4.gigabytes)
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:memory_policy, :guaranteed).and_return(2.gigabytes)
        # TODO: Add tests for when the highest_supported_api_version is 4
        allow(@ems).to receive(:supported_api_versions).and_return(%w(3))
        @rhevm_vm = double('rhevm_vm')
        allow(@rhevm_vm).to receive(:attributes).and_return(@rhevm_vm_attrs)
        allow(@vm).to receive(:with_provider_object).and_yield(@rhevm_vm)
      end

      it "cpu_topology=" do
        spec = {
          "numCPUs"           => @cores_per_socket * @num_of_sockets,
          "numCoresPerSocket" => @cores_per_socket
        }

        expect(@rhevm_vm).to receive(:cpu_topology=).with(:cores => @cores_per_socket, :sockets => @num_of_sockets)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end

      it 'updates the current and persistent configuration if the VM is up' do
        spec = {
          'memoryMB' => 8.gigabytes / 1.megabyte
        }
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:status, :state).and_return('up')
        expect(@rhevm_vm).to receive(:update_memory).with(8.gigabytes, 2.gigabytes, :next_run => true)
        expect(@rhevm_vm).to receive(:update_memory).with(8.gigabytes, nil)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end

      it 'updates only the persistent configuration when the VM is down' do
        spec = {
          'memoryMB' => 8.gigabytes / 1.megabyte
        }
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:status, :state).and_return('down')
        expect(@rhevm_vm).to receive(:update_memory).with(8.gigabytes, 2.gigabytes)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end

      it 'adjusts the increased memory to the next 256 MiB multiple if the VM is up' do
        spec = {
          'memoryMB' => 8.gigabytes / 1.megabyte + 1
        }
        adjusted = 8.gigabytes + 256.megabytes
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:status, :state).and_return('up')
        expect(@rhevm_vm).to receive(:update_memory).with(adjusted, 2.gigabytes, :next_run => true)
        expect(@rhevm_vm).to receive(:update_memory).with(adjusted, nil)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end

      it 'adjusts reduced memory to the next 256 MiB multiple if the VM is up' do
        spec = {
          'memoryMB' => 8.gigabytes / 1.megabyte - 1
        }
        adjusted = 8.gigabytes
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:status, :state).and_return('up')
        expect(@rhevm_vm).to receive(:update_memory).with(adjusted, 2.gigabytes, :next_run => true)
        expect(@rhevm_vm).to receive(:update_memory).with(adjusted, nil)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end

      it 'adjusts the guaranteed memory if it is larger than the virtual memory if the VM is up' do
        spec = {
          'memoryMB' => 1.gigabyte / 1.megabyte
        }
        adjusted = 1.gigabyte
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:status, :state).and_return('up')
        expect(@rhevm_vm).to receive(:update_memory).with(1.gigabyte, adjusted, :next_run => true)
        expect(@rhevm_vm).to receive(:update_memory).with(1.gigabyte, nil)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end

      it 'adjusts the guaranteed memory if it is larger than the virtual memory if the VM is down' do
        spec = {
          'memoryMB' => 1.gigabyte / 1.megabyte
        }
        adjusted = 1.gigabyte
        allow(@rhevm_vm_attrs).to receive(:fetch_path).with(:status, :state).and_return('down')
        expect(@rhevm_vm).to receive(:update_memory).with(1.gigabyte, adjusted)
        @ems.vm_reconfigure(@vm, :spec => spec)
      end
    end
  end

  context ".make_ems_ref" do
    it "removes the /ovirt-engine prefix" do
      expect(described_class.make_ems_ref("/ovirt-engine/api/vms/123")).to eq("/api/vms/123")
    end

    it "does not remove the /api prefix" do
      expect(described_class.make_ems_ref("/api/vms/123")).to eq("/api/vms/123")
    end
  end

  context ".extract_ems_ref_id" do
    it "extracts the resource ID from the href" do
      expect(described_class.extract_ems_ref_id("/ovirt-engine/api/vms/123")).to eq("123")
    end
  end

  context "api versions" do
    require 'ovirtsdk4'

    let(:ems) { FactoryGirl.create(:ems_redhat_with_authentication) }
    context 'when parsing database api_version' do
      let(:ems) { FactoryGirl.create(:ems_redhat, :api_version => api_version) }
      subject(:supported_api_versions) { ems.supported_api_versions }
      context "version 4.2" do
        let(:api_version) { "4.2.0" }
        it 'returns versions 3 and 4' do
          expect(supported_api_versions).to match_array(%w(3 4))
        end
      end

      context "version 3.6.1" do
        let(:api_version) { "3.6.1" }
        it 'returns versions 3' do
          expect(supported_api_versions).to match_array(%w(3))
        end
      end

      context "version 4.2.0-0.0.master.20170917124606.gita804ef7.el7.centos" do
        let(:api_version) { "4.2.0-0.0.master.20170917124606.gita804ef7.el7.centos" }
        it 'returns versions 3 and 4' do
          expect(supported_api_versions).to match_array(%w(3 4))
        end
      end

      context "version 4.2.1.3" do
        let(:api_version) { "4.2.1.3" }
        it 'returns versions 3 and 4' do
          expect(supported_api_versions).to match_array(%w(3 4))
        end
      end

      context "version 4.2.1a" do
        let(:api_version) { "4.2.1a" }
        it 'returns versions 3 and 4' do
          expect(supported_api_versions).to match_array(%w(3 4))
        end
      end

      context "version 4.3" do
        let(:api_version) { "4.3" }
        it 'returns versions 3 and 4' do
          expect(supported_api_versions).to match_array(%w(3 4))
        end
      end

      context "version 5.5" do
        let(:api_version) { "5.5" }
        it 'returns empty array' do
          expect(supported_api_versions).to match_array([])
        end
      end
    end

    context 'when probing provider directly' do
      subject(:supported_api_versions) { ems.supported_api_versions }
      context "#supported_api_versions" do
        it 'calls the OvirtSDK4::Probe.probe' do
          expect(OvirtSDK4::Probe).to receive(:probe).and_return([])
          supported_api_versions
        end

        it 'properly parses ProbeResults' do
          allow(OvirtSDK4::Probe).to receive(:probe)
            .and_return([OvirtSDK4::ProbeResult.new(:version => '3'),
                         OvirtSDK4::ProbeResult.new(:version => '4')])
          expect(supported_api_versions).to match_array(%w(3 4))
        end
      end
    end

    describe "#supports_the_api_version?" do
      it "returns the supported api versions" do
        allow(ems).to receive(:supported_api_versions).and_return([3])
        expect(ems.supports_the_api_version?(3)).to eq(true)
        expect(ems.supports_the_api_version?(6)).to eq(false)
      end
    end
  end

  context "supported features" do
    let(:ems) { FactoryGirl.create(:ems_redhat) }
    let(:supported_api_versions) { [3, 4] }
    context "#process_api_features_support" do
      before(:each) do
        allow(SupportsFeatureMixin).to receive(:guard_queryable_feature).and_return(true)
        allow(described_class).to receive(:api_features)
          .and_return('3' => %w(feature1 feature3), '4' => %w(feature2 feature3))
        described_class.process_api_features_support
        allow(ems).to receive(:supported_api_versions).and_return(supported_api_versions)
      end

      context "no versions supported" do
        let(:supported_api_versions) { [] }
        it 'supports the right features' do
          expect(ems.supports_feature1?).to be_falsey
          expect(ems.supports_feature2?).to be_falsey
          expect(ems.supports_feature3?).to be_falsey
        end
      end

      context "version 3 supported" do
        let(:supported_api_versions) { [3] }
        it 'supports the right features' do
          expect(ems.supports_feature1?).to be_truthy
          expect(ems.supports_feature2?).to be_falsey
          expect(ems.supports_feature3?).to be_truthy
        end
      end

      context "version 4 supported" do
        let(:supported_api_versions) { [4] }
        it 'supports the right features' do
          expect(ems.supports_feature1?).to be_falsey
          expect(ems.supports_feature2?).to be_truthy
          expect(ems.supports_feature3?).to be_truthy
        end
      end

      context "all versions supported" do
        let(:supported_api_versions) { [3, 4] }
        it 'supports the right features' do
          expect(ems.supports_feature1?).to be_truthy
          expect(ems.supports_feature2?).to be_truthy
          expect(ems.supports_feature3?).to be_truthy
        end
      end
    end
  end

  context "#version_at_least?" do
    let(:api_version) { "4.2" }
    let(:ems) { FactoryGirl.create(:ems_redhat, :api_version => api_version) }

    context "api version is higher or equal than checked version" do
      it 'supports the right features' do
        expect(ems.version_at_least?("4.1")).to be_truthy

        ems.api_version = "4.1.3.2-0.1.el7"
        expect(ems.version_at_least?("4.1")).to be_truthy

        ems.api_version = "4.2.0_master"
        expect(ems.version_at_least?("4.1")).to be_truthy

        ems.api_version = "4.2.1_master"
        expect(ems.version_at_least?("4.2.0")).to be_truthy
      end
    end

    context "api version is lowergit  than checked version" do
      let(:api_version) { "4.0" }
      it 'supports the right features' do
        expect(ems.version_at_least?("4.1")).to be_falsey

        ems.api_version = "4.0.3.2-0.1.el7"
        expect(ems.version_at_least?("4.1")).to be_falsey

        ems.api_version = "4.0.0_master"
        expect(ems.version_at_least?("4.1")).to be_falsey

        ems.api_version = "4.0.1_master"
        expect(ems.version_at_least?("4.0.2")).to be_falsey
      end
    end

    context "api version not set" do
      let(:api_version) { nil }
      it 'always return false' do
        expect(ems.version_at_least?("10.1")).to be_falsey

        expect(ems.version_at_least?("0")).to be_falsey
      end
    end
  end

  context ".raw_connect" do
    let(:options) do
      {
        :username => 'user',
        :password => 'pword'
      }
    end
    let(:v4_connection) { double(OvirtSDK4::Connection) }
    let(:v3_connection) { double(Ovirt::Service) }

    before do
      allow(v3_connection).to receive(:disconnect)
    end

    it "works with version 4" do
      expect(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      expect(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
        .and_return(true)

      described_class.raw_connect(options)
    end

    it "works with version 3" do
      expect(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      expect(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
        .and_raise(OvirtSDK4::Error.new('Something failed'))
      expect(described_class).to receive(:raw_connect_v3).and_return(v3_connection)
      expect(v3_connection).to receive(:api).and_return(nil)

      described_class.raw_connect(options)
    end

    it "always closes the V3 connection" do
      expect(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      expect(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
        .and_raise(OvirtSDK4::Error.new('Something failed'))
      expect(described_class).to receive(:raw_connect_v3).and_return(v3_connection)
      expect(v3_connection).to receive(:api).and_return(nil)
      expect(v3_connection).to receive(:disconnect)

      described_class.raw_connect(options)
    end

    it "decrypts the password" do
      allow(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      expect(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
        .and_return(true)

      expect(MiqPassword).to receive(:try_decrypt).with(options[:password])

      described_class.raw_connect(options)
    end
  end

  context "network manager validations" do
    let(:api_version) { "4.2" }

    before do
      @ems = FactoryGirl.create(:ems_redhat, :api_version => api_version)
      @provider = double(:authentication_url => 'https://hostname.usersys.redhat.com:35357/v2.0')
      @providers = double("providers", :sort_by => [@provider], :first => @provider)
      allow(@ems).to receive(:ovirt_services).and_return(double(:collect_external_network_providers => @providers))
      @ems.ensure_managers
    end

    it "does not create orphaned network_manager" do
      expect(ExtManagementSystem.count).to eq(2)
      same_ems = ExtManagementSystem.find(@ems.id)
      allow(same_ems).to receive(:ovirt_services).and_return(double(:collect_external_network_providers => @providers))

      @ems.destroy
      expect(ExtManagementSystem.count).to eq(0)

      same_ems.hostname = "dummy-mandatory"
      same_ems.ensure_managers
      expect(ExtManagementSystem.count).to eq(0)
    end

    context "network manager url is valid" do
      it "returns the correct hostname" do
        expect(@ems.network_manager.hostname).to eq "hostname.usersys.redhat.com"
      end
      it "returns the correct port" do
        expect(@ems.network_manager.port).to eq(35357)
      end
      it "returns the correct version" do
        expect(@ems.network_manager.api_version).to eq("v2")
      end
      it "returns the correct security protocol" do
        expect(@ems.network_manager.security_protocol).to eq("ssl")
      end
    end
  end

  context 'catalog types' do
    let(:ems) { FactoryGirl.create(:ems_redhat) }

    it "#supported_catalog_types" do
      expect(ems.supported_catalog_types).to eq(%w(redhat))
    end
  end
end
