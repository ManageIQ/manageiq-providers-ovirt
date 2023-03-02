describe ManageIQ::Providers::Ovirt::InfraManager do
  it ".ems_type" do
    expect(described_class.ems_type).to eq('ovirt')
  end

  it ".description" do
    expect(described_class.description).to eq('oVirt')
  end

  describe ".metrics_collector_queue_name" do
    it "returns the correct queue name" do
      worker_queue = ManageIQ::Providers::Ovirt::InfraManager::MetricsCollectorWorker.default_queue_name
      expect(described_class.metrics_collector_queue_name).to eq(worker_queue)
    end
  end

  describe "rhevm_metrics_connect_options" do
    let(:ems) { FactoryBot.create(:ems_ovirt, :hostname => "some.thing.tld") }

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
        FactoryBot.create(:ems_ovirt,
                          :hostname                  => "some.thing.tld",
                          :connection_configurations => [{:endpoint => {:role => :metrics,
                                                                        :path => "some.database"}}])
      end

      it "fetches the set database name" do
        expect(ems.rhevm_metrics_connect_options[:database]).to eq("some.database")
      end
    end
  end

  describe "#verify_credentials" do
    let(:ems) { FactoryBot.create(:ems_ovirt) }

    context "metrics" do
      it 'raises MiqEVMLoginError in case of connection error' do
        msg = "FATAL:  no pg_hba.conf entry for host ...."
        allow(OvirtMetrics).to receive(:connect).and_raise(PG::ConnectionBad, msg)
        expect { ems.verify_credentials('metrics') }.to raise_error(MiqException::MiqEVMLoginError)
      end
    end
  end

  context "#vm_reconfigure" do
    let!(:zone) do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end

    let!(:ems) { FactoryBot.create(:ems_ovirt_with_authentication, :zone => zone) }
    let!(:vm) { FactoryBot.create(:vm_ovirt, :ext_management_system => ems) }
    let(:ovirt_services_instance) { instance_double(ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::V4) }

    it 'sends vm_reconfigure to ovirt_services' do
      allow(ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::V4)
        .to receive(:new)
        .and_return(ovirt_services_instance)

      expect(ovirt_services_instance).to receive(:vm_reconfigure).with(vm, {})

      ems.vm_reconfigure(vm)
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

  context "supported features" do
    let(:ems) { FactoryBot.create(:ems_ovirt) }
    context "#process_api_features_support" do
      before(:each) do
        allow(SupportsFeatureMixin).to receive(:guard_queryable_feature).and_return(true)
        described_class.process_api_features_support
      end

      context "all supported regardless the version" do
        it "all defined features supported" do
          described_class::SUPPORTED_FEATURES.each do |f|
            expect(ems.supports?(f)).to be_truthy
          end
        end
      end

      context "also with blank api_version" do
        let(:ems) { FactoryBot.create(:ems_ovirt, :api_version => api_version) }
        let(:api_version) { '' }
        it "all features supported" do
          described_class::SUPPORTED_FEATURES.each do |f|
            expect(ems.supports?(f)).to be_truthy
          end
        end
      end
    end
  end

  context "#version_at_least?" do
    let(:api_version) { "4.2" }
    let(:ems) { FactoryBot.create(:ems_ovirt, :api_version => api_version) }

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

  context ".verify_credentials" do
    let(:default_authentication) { {"userid" => "user", "password" => "pword"} }
    let(:default_endpoint)       { {"hostname" => "ovirt.localdomain", "port" => 443} }
    let(:metrics_authentication) { nil }
    let(:metrics_endpoint)       { nil }

    let(:params) do
      {
        "endpoints"       => {
          "default" => default_endpoint,
          "metrics" => metrics_endpoint
        },
        "authentications" => {
          "default" => default_authentication,
          "metrics" => metrics_authentication
        }
      }
    end

    it "calls check_connect_api" do
      expect(described_class).to receive(:check_connect_api).with(hash_including(:username => "user", :password => "pword", :server => "ovirt.localdomain", :port => 443)).and_return(true)
      described_class.verify_credentials(params)
    end

    context "with verify_ssl VERIFY_PEER" do
      let(:default_endpoint) { {"hostname" => "ovirt.localdomain", "port" => 443, "verify_ssl" => OpenSSL::SSL::VERIFY_PEER} }

      it "calls check_connect_api with verify_ssl" do
        expect(described_class).to receive(:check_connect_api).with(hash_including(:verify_ssl => OpenSSL::SSL::VERIFY_PEER)).and_return(true)
        described_class.verify_credentials(params)
      end
    end

    context "with trusted CA certificates" do
      let(:default_endpoint) { {"hostname" => "ovirt.localdomain", "port" => 443, "verify_ssl" => OpenSSL::SSL::VERIFY_PEER, "certificate_authority" => ca} }
      let(:ca) { "----- BEGIN CERTIFICATE -----\n----- END CERTIFICATE -----\n" }

      it "calls check_connect_api with verify_ssl" do
        expect(described_class).to receive(:check_connect_api).with(hash_including(:verify_ssl => OpenSSL::SSL::VERIFY_PEER, :ca_certs => ca)).and_return(true)
        described_class.verify_credentials(params)
      end
    end

    context "with a metrics endpoint" do
      let(:metrics_authentication) { {"userid" => "psql", "password" => "postgres"} }
      let(:metrics_endpoint)       { {"hostname" => "ovirt.localdomain", "port" => 5432, "path" => "ovirt_engine_history"} }

      it "calls check_connect_api and check_connect_metrics" do
        expect(described_class).to receive(:check_connect_api).with(hash_including(:username => "user", :password => "pword", :server => "ovirt.localdomain", :port => 443)).and_return(true)
        expect(described_class).to receive(:check_connect_metrics).with(hash_including(:metrics_username => "psql", :metrics_password => "postgres", :metrics_server => "ovirt.localdomain", :metrics_port => 5432)).and_return(true)
        described_class.verify_credentials(params)
      end
    end
  end

  context ".raw_connect" do
    let(:options) do
      {
        :server   => 'ovirt.localdomain',
        :username => 'user',
        :password => 'pword'
      }
    end
    let(:v4_connection) { double(OvirtSDK4::Connection) }

    it "works with version 4" do
      expect(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      expect(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
                                             .and_return(true)

      described_class.raw_connect(options)
    end

    it "decrypts the password" do
      allow(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      expect(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
                                             .and_return(true)

      expect(ManageIQ::Password).to receive(:try_decrypt).with(options[:password])

      described_class.raw_connect(options)
    end

    it "handle credential validation error" do
      opts = options.merge({:metrics_server => 'server'})

      allow(described_class).to receive(:raw_connect_v4).and_return(v4_connection)
      allow(v4_connection).to receive(:test).with(hash_including(:raise_exception => true))
                                             .and_return(true)
      allow(OvirtMetrics).to receive(:connect).and_raise(ArgumentError)

      expect { described_class.raw_connect(opts) }.to raise_error(MiqException::MiqEVMLoginError)
    end
  end

  context "network manager validations" do
    let(:api_version) { "4.2" }

    before do
      @ems = FactoryBot.create(:ems_ovirt, :api_version => api_version)
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

    it "removes network manager" do
      zone = FactoryBot.create(:zone)
      allow(MiqServer).to receive(:my_zone).and_return(zone.name)
      allow(@ems).to receive(:ovirt_services).and_return(double(:collect_external_network_providers => {}))
      expect(ExtManagementSystem.count).to eq(2)
      @ems.ensure_managers
      deliver_queue_messages
      expect(ExtManagementSystem.count).to eq(1)
    end

    def deliver_queue_messages
      MiqQueue.order(:id).each do |queue_message|
        status, message, result = queue_message.deliver
        queue_message.delivered(status, message, result)
      end
    end
  end

  context 'catalog types' do
    let(:ems) { FactoryBot.create(:ems_ovirt) }

    it "#catalog_types" do
      expect(ems.catalog_types).to include("ovirt")
    end
  end

  context 'vm_migration' do
    before do
      @ems = FactoryBot.create(:ems_ovirt)
      @vm = FactoryBot.create(:vm_ovirt, :ext_management_system => @ems)

      service = double
      allow(service).to receive(:migrate).with(:host => {:id => "11089411-53a2-4337-8613-7c1d411e8ae8"})
      allow(@ems).to receive(:with_vm_service).and_return(service)
    end

    it "succeeds migration" do
      ems_event = FactoryBot.create(:ems_event, :event_type => "VM_MIGRATION_DONE", :message => "migration done", :ext_management_system => @ems, :vm => @vm, :timestamp => Time.zone.now + 1)
      @vm.ems_events << ems_event

      expect { @ems.vm_migrate(@vm, {:host => "/ovirt-engine/api/hosts/11089411-53a2-4337-8613-7c1d411e8ae8"}, 1) }.to_not raise_error
    end

    it "fails migration" do
      ems_event = FactoryBot.create(:ems_event, :event_type => "VM_MIGRATION_FAILED_FROM_TO", :message => "migration failed", :ext_management_system => @ems, :vm => @vm, :timestamp => Time.zone.now + 1)
      @vm.ems_events << ems_event

      expect { @ems.vm_migrate(@vm, {:host => "/ovirt-engine/api/hosts/11089411-53a2-4337-8613-7c1d411e8ae8"}, 1) }.to raise_error(ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error)
    end

    it "never receives an event" do
      expect { @ems.vm_migrate(@vm, {:host => "/ovirt-engine/api/hosts/11089411-53a2-4337-8613-7c1d411e8ae8"}, 1, 2) }.to raise_error(ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::Error)
    end
  end
end
