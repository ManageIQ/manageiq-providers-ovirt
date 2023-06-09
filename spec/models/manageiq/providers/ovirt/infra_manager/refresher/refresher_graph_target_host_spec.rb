require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon
  include Spec::Support::EmsRefreshHelper

  describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
    before(:each) do
      init_defaults
      init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/ovirt_sdk_refresh_graph_target_host.yml')

      @ovirt_service_inventory = ManageIQ::Providers::Ovirt::InfraManager::Inventory
      allow_any_instance_of(@ovirt_service_inventory)
                       .to receive(:collect_vnic_profiles).and_return([])
      @collector = ManageIQ::Providers::Ovirt::Inventory::Collector
      allow_any_instance_of(@collector)
                       .to receive(:collect_vnic_profiles).and_return([])
    end

    it 'does not change the host when target refresh after full refresh' do
      EmsRefresh.refresh(@ems)
      @ems.reload

      saved_inventory = serialize_inventory

      host = @ems.hosts.find_by(:ems_ref => "/api/hosts/9be35c00-6523-4c2f-89d2-680a6b6da4c0")
      EmsRefresh.refresh(host)
      host.reload
      assert_inventory_not_changed(saved_inventory, serialize_inventory)
      host.update_attribute(:ipmi_address, "127.0.0.1")
      host.update_authentication(:ipmi => {:userid => "a", :password => "a"})
      EmsRefresh.refresh(host)
      host.reload

      expect(Host.count).to eq(2)
      expect(host.ipmi_address).to eq("127.0.0.1")
      expect(host.authentications.first.userid).to eq("a")
      expect(host.switches.map { |switch| [switch.uid_ems, switch.name] }).to contain_exactly(
        a_collection_containing_exactly("b6a660fd-f1ff-4d26-b535-91fae6d42a3f", "ovirtmgmt")
      )
    end

    def host_to_comparable_hash(host)
      host.attributes.except("updated_on", "state_changed_on")
    end
  end
end
