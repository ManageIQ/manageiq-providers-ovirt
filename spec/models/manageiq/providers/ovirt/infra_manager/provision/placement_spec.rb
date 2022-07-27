describe ManageIQ::Providers::Ovirt::InfraManager::Provision do
  context "::Placement" do
    before do
      ems      = FactoryBot.create(:ems_ovirt_with_authentication)
      template = FactoryBot.create(:template_ovirt, :ext_management_system => ems)
      vm       = FactoryBot.create(:vm_ovirt)
      @cluster = FactoryBot.create(:ems_cluster, :ext_management_system => ems)
      options  = {:src_vm_id => template.id}

      @task = FactoryBot.create(:miq_provision_ovirt, :source      => template,
                                                        :destination => vm,
                                                        :state       => 'pending',
                                                        :status      => 'Ok',
                                                        :options     => options)
    end

    it "#manual_placement raise error" do
      @task.options[:placement_auto] = false
      expect { @task.send(:placement) }.to raise_error(MiqException::MiqProvisionError)
    end

    it "#manual_placement" do
      @task.options[:placement_cluster_name] = @cluster.id
      @task.options[:placement_auto]         = false
      check
    end

    it "#automatic_placement" do
      expect(@task).to receive(:get_placement_via_automate).and_return(:cluster => @cluster)
      @task.options[:placement_auto]         = true
      check
    end

    it "automate returns nothing" do
      @task.options[:placement_cluster_name] = @cluster.id
      expect(@task).to receive(:get_placement_via_automate).and_return({})
      @task.options[:placement_auto]         = true
      check
    end

    def check
      @task.send(:placement)
      expect(@task.options[:dest_cluster]).to eql([@cluster.id, @cluster.name])
    end
  end
end
