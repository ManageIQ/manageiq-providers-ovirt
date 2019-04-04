require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
    before(:each) do
      init_defaults(:hostname => "bodnopoz-engine.eng.lab.tlv.redhat.com", :ipaddress => "10.35.19.13", :port => 443 )
      init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_graph_target_host.yml')

      @ovirt_service_inventory = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4
      allow_any_instance_of(@ovirt_service_inventory)
                       .to receive(:collect_vnic_profiles).and_return([])
      @collector = ManageIQ::Providers::Redhat::Inventory::Collector
      allow_any_instance_of(@collector)
                       .to receive(:collect_vnic_profiles).and_return([])

      stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
      stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    end

    let(:models_for_host_target) { [ExtManagementSystem, EmsFolder, EmsCluster, Storage, HostStorage, Switch, HostSwitch, Lan, CustomAttribute] }

    it 'does not change the host when target refresh after full refresh' do

      EmsRefresh.refresh(@ems)
      @ems.reload

      saved_inventory = serialize_inventory(models_for_host_target)

      host = @ems.hosts.find_by(:ems_ref => "/api/hosts/f9dbfd16-3c79-4028-9304-9acf3b8857ba")
      EmsRefresh.refresh(host)
      host.reload

      expect(serialize_inventory(models_for_host_target)).to eq(saved_inventory)

      EmsRefresh.refresh(host)
      host.reload

      expect(host.switches.map { |switch| [switch.uid_ems, switch.name] }).to contain_exactly(
        a_collection_containing_exactly("00000000-0000-0000-0000-000000000009", "ovirtmgmt"),
        a_collection_containing_exactly("5c42817f-03fb-460e-a3ab-a8770553aeee", "vlan123t")
      )
    end

    def host_to_comparable_hash(host)
      host.attributes.except("updated_on", "state_changed_on")
    end
  end
end
