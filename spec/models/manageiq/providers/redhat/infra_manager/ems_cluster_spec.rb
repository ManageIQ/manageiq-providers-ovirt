describe ManageIQ::Providers::Redhat::InfraManager::EmsCluster do
  context "#upgrade" do
    before do
      @ems = FactoryGirl.create(:ems_redhat_with_authentication)
      @cluster = FactoryGirl.create(:ems_cluster_redhat, :ems_id => @ems.id)
      my_server = double("my_server", :guid => "guid1")
      allow(MiqServer).to receive(:my_server).and_return(my_server)
    end
    it "sends the right parameters to the upgrade" do
      env_vars = {}
      extra_args = {:engine_url      => "https://#{@ems.address}/ovirt-engine/api",
                    :engine_user     => @ems.authentication_userid,
                    :engine_password => @ems.authentication_password,
                    :cluster_name    => @cluster.name,
                    :hostname        => "localhost"}
      role_arg = {:role_name=>"oVirt.cluster-upgrade"}
      expect(ManageIQ::Providers::AnsibleRoleWorkflow).to receive(:create_job).with(env_vars, extra_args, role_arg).and_call_original
      @cluster.upgrade
    end
  end
end
