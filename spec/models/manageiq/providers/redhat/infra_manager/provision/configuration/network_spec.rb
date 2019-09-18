require "ovirt"

describe ManageIQ::Providers::Redhat::InfraManager::Provision::Configuration::Network do
  let(:mac_address)   { "mac_address" }
  let(:network_id)    { "network1-id" }
  let(:network_name)  { "network1-name" }
  let(:rhevm_cluster) { double("Ovirt::Cluster") }
  let(:ems)           { FactoryBot.create(:ems_redhat_with_authentication) }
  let(:ems_cluster)   { FactoryBot.create(:ems_cluster, :ext_management_system => ems, :ems_ref => "ems_ref", :uid_ems => "cluster_uid_ems") }
  let(:template)      { FactoryBot.create(:template_redhat, :ext_management_system => ems) }
  let(:rhevm_vm)      { double("Ovirt::Vm") }
  let(:target_vm)     { FactoryBot.create(:vm_redhat, :ext_management_system => ems) }
  let(:ovirt_service) { double("Ovirt::Service", :api_path => "/api") }

  before do
    @task = FactoryBot.create(:miq_provision_redhat,
                               :source      => template,
                               :destination => target_vm,
                               :state       => 'pending',
                               :status      => 'Ok',
                               :options     => {:src_vm_id => template.id})
    allow(@task).to receive_messages(
      :dest_cluster => ems_cluster,
      :source       => template,
    )
    allow(@task).to receive(:get_provider_destination).and_yield(rhevm_vm)

    allow(Ovirt::Service).to receive_messages(:new => ovirt_service)

    allow(template).to receive_messages(:ext_management_system => ems)
    allow(Ovirt::Cluster).to receive(:find_by_href).with(kind_of(ManageIQ::Providers::Redhat::InfraManager::ApiIntegration::OvirtConnectionDecorator), ems_cluster.ems_ref).and_return(rhevm_cluster)
    allow(rhevm_cluster).to receive(:find_network_by_name).with(network_name).and_return(:id => network_id)
    allow(target_vm).to receive(:provider_object).and_return(rhevm_vm)
  end

  context "#configure_network_adapters" do
    context "ems version 4" do
      let(:rhevm_nic1) { double(:id => "nic1-id", :name => "nic1", :network => {:id => network_id}, :mac => ovirtSDK4_mac, :vnic_profile => vnic_profile_1) }
      let(:rhevm_nic2) { double(:id => "nic2-id", :name => "nic2", :network => {:id => "network2-id"}, :vnic_profile => vnic_profile_2) }
      let(:vm_proxy) { "vm_proxy" }
      let(:system_service) { double("system_service", :vms_service => vms_service, :vnic_profiles_service => vnic_profiles_service, :clusters_service => clusters_service) }
      let(:connection) { double("connection", :system_service => system_service) }
      let(:vms_service) { double("vms_service", :vm_service => vm_service) }
      let(:vm_service) { double("vm_service", :nics_service => nics_service) }
      let(:nics_service) { "nics_service" }
      let(:nic1_service) { "nic1_service" }
      let(:nic2_service) { "nic2_service" }
      let(:clusters_service) { double("clusters_service") }
      let(:cluster_service1) { double("cluster", :networks_service => networks_service) }
      let(:networks_service) { "networks_service" }
      let(:network) { double(:id => network_id, :name => "network") }
      let(:network_id) { "network_id" }
      let(:vnic_profiles_service) { "vnic_profiles_service" }
      let(:vnic_profile_id) { "vnic_profile_id" }
      let(:vnic_profile_1) { double("vnic_prof1", :id => vnic_profile_id) }
      let(:vnic_profile_2) { double("vnic_prof2", :id => "vnic_profile_id_2") }
      let(:vnic_profile_name) { "vnic_profile_name" }
      let(:network_profile) { double(:id => vnic_profile_id, :name => vnic_profile_name, :network => double(:id => network_id)) }
      let(:ovirtSDK4_mac) { OvirtSDK4::Mac.new(:address => mac_address) }

      before do
        stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
        allow_any_instance_of(ManageIQ::Providers::Redhat::InfraManager).to receive(:supported_api_versions)
          .and_return([3, 4])
        allow(ems.ovirt_services).to receive(:get_vm_proxy).and_return(rhevm_vm)
        allow(rhevm_vm).to receive_messages(:nics => [rhevm_nic1, rhevm_nic2], :ext_management_system => ems)
        allow(ems).to receive(:with_provider_connection).and_yield(connection)
        allow(nics_service).to receive(:nic_service)
          .with(rhevm_nic1.id) { nic1_service }
        allow(nics_service).to receive(:nic_service)
          .with(rhevm_nic2.id) { nic2_service }
        allow(vm_service).to receive(:get).and_return(vm_proxy)
        allow(vm_proxy).to receive(:nics)
        allow(connection).to receive(:follow_link).with(vm_proxy.nics) { rhevm_vm.nics }
        allow(rhevm_nic1).to receive(:name)
        allow(rhevm_nic2).to receive(:name)
        allow(clusters_service).to receive(:cluster_service).with(any_args).and_return(cluster_service1)
        allow(vnic_profiles_service).to receive(:list).and_return([network_profile])
        allow(networks_service).to receive(:list).and_return([network])
      end
      context "add second NIC in automate" do
        before do
          @task.options[:networks] = [nil, {:network => vnic_profile_id}]
        end

        it "first NIC from dialog" do
          assign_vnic_profile(vnic_profile_id)

          expect(nic1_service).to receive(:update)
          expect(nic2_service).to receive(:update)

          @task.configure_network_adapters

          expect(@task.options[:networks]).to match_array([
                                                            {:network => vnic_profile_id, :mac_address => nil},
                                                            {:network => vnic_profile_id}
                                                          ])
        end

        it "no NIC from dialog" do
          expect(nic1_service).to receive(:remove)
          expect(nic2_service).to receive(:update)

          @task.configure_network_adapters
        end
      end

      it "dialog NIC only" do
        assign_vnic_profile(vnic_profile_id)

        expect(nic1_service).to receive(:update)
        expect(nic2_service).to receive(:remove)

        @task.configure_network_adapters
      end

      it "no NICs" do
        @task.configure_network_adapters
      end

      context "update NICs" do
        it "should update an existing adapter's network" do
          @task.options[:networks] = [{:network => vnic_profile_id}]

          expect(rhevm_vm).to receive(:nics).and_return([rhevm_nic1])
          expect(nic1_service).to receive(:update).with(:name => "nic1", :vnic_profile => {:id => vnic_profile_id})

          @task.configure_network_adapters
        end

        it "should update an existing adapter's network using 'profile_id (network_name)'" do
          @task.options[:networks] = [{:network => get_profile_description(vnic_profile_name, network.name)}]

          expect(rhevm_vm).to receive(:nics).and_return([rhevm_nic1])
          expect(nic1_service).to receive(:update).with(:name => "nic1", :vnic_profile => {:id => vnic_profile_id})

          @task.configure_network_adapters
        end

        it "should update an existing adapter's network with 'Empty' profile" do
          @task.options[:networks] = [{:network => '<Empty>'}]

          expect(rhevm_vm).to receive(:nics).and_return([rhevm_nic1])
          expect(nic1_service).to receive(:update).with(:name => "nic1", :vnic_profile => {:id => nil})

          @task.configure_network_adapters
        end

        it "should update an existing adapter's MAC address" do
          @task.options[:networks] = [{:network => vnic_profile_id, :mac_address => mac_address}]

          expect(rhevm_vm).to receive(:nics).and_return([rhevm_nic1])
          expect(nic1_service).to receive(:update).with(
            :name         => "nic1",
            :vnic_profile => {:id => vnic_profile_id},
            :mac          => ovirtSDK4_mac
          )

          @task.configure_network_adapters
        end
      end

      it "should create a new adapter with an optional MAC address" do
        @task.options[:networks] = [{:network => vnic_profile_id, :mac_address => mac_address}]

        expect(rhevm_vm).to receive(:nics).and_return([])
        expect(nics_service).to receive(:add)
        expect(OvirtSDK4::Nic).to receive(:new).with(
          :name         => 'nic1',
          :vnic_profile => {:id => "vnic_profile_id"},
          :mac          => ovirtSDK4_mac
        )

        @task.configure_network_adapters
      end

      context "#get_mac_address_of_nic_on_requested_vlan" do
        before do
          allow(ems.ovirt_services).to receive(:nics_for_vm).with(target_vm).and_return([rhevm_nic1, rhevm_nic2])
        end

        context "profile_id is <Template>" do
          before do
            assign_vnic_profile('<Template>')
          end

          it 'nics list is empty' do
            test_empty_nic_list
          end

          it 'nics list is not empty' do
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(mac_address)
          end
        end

        context "profile_id is <Empty>" do
          before do
            assign_vnic_profile('<Empty>')
          end

          it 'nics list is empty' do
            test_empty_nic_list
          end

          it 'nics list contains a nic with no profile' do
            allow(rhevm_nic1).to receive(:vnic_profile).and_return(nil)
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(mac_address)
          end

          it 'nics list does not contain a nic with no profile' do
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(nil)
          end
        end

        context "profile_id is specified" do
          before do
            assign_vnic_profile(vnic_profile_id)
          end

          it 'nics list is empty' do
            test_empty_nic_list
          end

          it 'nics list contains a nic with the specified profile_id' do
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(mac_address)
          end

          it 'nics list does not contain a nic with the specified profile_id' do
            allow(rhevm_nic1).to receive(:vnic_profile).and_return(vnic_profile_2)
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(nil)
          end
        end

        context "'profile_id (network_name)' is specified" do
          before do
            assign_vnic_profile(get_profile_description(vnic_profile_name, network.name))
          end

          it 'returns mac address since nics list contains a nic with the specified profile description' do
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(mac_address)
          end

          it 'returns nil since nics list does not contain a nic with the specified profile description' do
            allow(rhevm_nic1).to receive(:vnic_profile).and_return(vnic_profile_2)
            expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(nil)
          end
        end
      end

      def assign_vnic_profile(vnic_profile_id)
        @task.options[:vlan] = [vnic_profile_id, get_profile_description(vnic_profile_name, network_name)]
      end

      def get_profile_description(vnic_profile_name, network_name)
        "#{vnic_profile_name} (#{network_name})"
      end

      def test_empty_nic_list
        allow(ems.ovirt_services).to receive(:nics_for_vm).with(target_vm).and_return([])
        expect(@task.get_mac_address_of_nic_on_requested_vlan).to eq(nil)
      end
    end
  end
end
