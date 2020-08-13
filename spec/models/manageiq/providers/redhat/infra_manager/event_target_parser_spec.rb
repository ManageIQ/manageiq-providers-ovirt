describe ManageIQ::Providers::Redhat::InfraManager::EventTargetParser do
  let!(:ems) { FactoryBot.create(:ems_redhat) }
  let(:event_type) { "USER_ADD_VM" }
  let(:ems_event) do
    FactoryBot.create(:ems_event, :ext_management_system => ems, :event_type => event_type, :full_data => event_data, :source => "RHEVM")
  end

  context "with a vm target" do
    let(:event_data) { {"name"=>"USER_ADD_VM", "vm" => {"href" => "/ovirt-engine/api/vms/3f1286a4-e16a-44b6-a0c1-2c88837b1313"}} }

    it "parses USER_ADD_VM" do
      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.count).to eq(1)

      vm_target = parsed_targets.first
      expect(vm_target.association).to eq(:vms)
      expect(vm_target.manager_ref).to eq(:ems_ref => "/api/vms/3f1286a4-e16a-44b6-a0c1-2c88837b1313")
    end
  end

  context "with a template target" do
    let(:event_data) { {"name"=>"USER_ADD_VM", "template" => {"href" => "/ovirt-engine/api/templates/c6e9bf1b-5673-4156-bf83-e8454cdff500"}} }

    it "parses USER_ADD_VM" do
      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.count).to eq(1)

      template_target = parsed_targets.first
      expect(template_target.association).to eq(:miq_templates)
      expect(template_target.manager_ref).to eq(:ems_ref => "/api/templates/c6e9bf1b-5673-4156-bf83-e8454cdff500")
    end
  end

  context "with a cluster target" do
    let(:event_data) { {"name"=>"USER_ADD_VM", "cluster" => {"href" => "/ovirt-engine/api/clusters/1d67acd6-9717-11e8-bec7-001a4a161155"}} }

    it "parses USER_ADD_VM" do
      parsed_targets = described_class.new(ems_event).parse

      expect(parsed_targets.count).to eq(1)

      cluster_target = parsed_targets.first
      expect(cluster_target.association).to eq(:ems_clusters)
      expect(cluster_target.manager_ref).to eq(:ems_ref => "/api/clusters/1d67acd6-9717-11e8-bec7-001a4a161155")
    end
  end
end
