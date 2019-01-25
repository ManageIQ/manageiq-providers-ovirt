describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
    before(:each) do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryGirl.create(:ems_redhat, :zone => zone, :hostname => "bodnopoz-engine.eng.lab.tlv.redhat.com", :ipaddress => "10.35.19.13",
                                :port => 443)
      @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
      allow_any_instance_of(@ovirt_service)
        .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
      @ovirt_service_inventory = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4
      allow_any_instance_of(@ovirt_service_inventory)
        .to receive(:collect_vnic_profiles).and_return([])
      @collector = ManageIQ::Providers::Redhat::Inventory::Collector
      allow_any_instance_of(@collector)
        .to receive(:collect_vnic_profiles).and_return([])
      @ems.update_authentication(:default => {:userid => "admin@internal", :password => "123456"})
      @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
      allow(@ems).to receive(:supported_api_versions).and_return(%w(3 4))
      stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
      allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original
      allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
        Spec::Support::OvirtSDK::ConnectionVCR.new(opts,
                                                   'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_graph_target_host.yml',
                                                   false)
      end
      stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
    end

    COUNTED_MODELS = [CustomAttribute, EmsFolder, EmsCluster, Datacenter].freeze

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

    it 'does not change the host when target refresh after full refresh' do
      stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
      EmsRefresh.refresh(@ems)
      @ems.reload
      host = @ems.hosts.find_by(:ems_ref => "/api/hosts/f9dbfd16-3c79-4028-9304-9acf3b8857ba")
      saved_host = host_to_comparable_hash(host)
      saved_counted_models = COUNTED_MODELS.map { |m| [m.name, m.count] }
      saved_storages = host.storages.map { |storage| [storage.id, storage.location, storage.name] }
      saved_switches = host.switches.map { |switch| [switch.id, switch.uid_ems, switch.name] }
      saved_lans     = host.lans.map     { |lan| [lan.id, lan.uid_ems, lan.name] }
      expect(host.networks.count).to eq(2)
      EmsRefresh.refresh(host)
      host.reload
      expect(host.networks.count).to eq(2)
      expect(saved_storages).to contain_exactly(*host.storages.map { |storage| a_collection_containing_exactly(storage.id, storage.location, storage.name) })
      expect(saved_switches).to contain_exactly(*host.switches.map { |switch| a_collection_containing_exactly(switch.id, switch.uid_ems, switch.name) })
      expect(saved_lans).to contain_exactly(*host.lans.map { |lan| a_collection_containing_exactly(lan.id, lan.uid_ems, lan.name) })
      EmsRefresh.refresh(host)
      host.reload
      expect(host.switches.map { |switch| [switch.uid_ems, switch.name] }).to contain_exactly(
        a_collection_containing_exactly("00000000-0000-0000-0000-000000000009", "ovirtmgmt"),
        a_collection_containing_exactly("5c42817f-03fb-460e-a3ab-a8770553aeee", "vlan123t")
      )
      expect(host.networks.count).to eq(2)
      counted_models = COUNTED_MODELS.map { |m| [m.name, m.count] }
      expect(saved_host).to eq(host_to_comparable_hash(host))
      expect(saved_counted_models).to eq(counted_models)
    end

    def host_to_comparable_hash(host)
      host.attributes.except("updated_on", "state_changed_on")
    end
  end
end
