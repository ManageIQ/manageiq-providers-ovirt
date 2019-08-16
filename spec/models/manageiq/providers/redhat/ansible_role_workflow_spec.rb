describe ManageIQ::Providers::Redhat::AnsibleRoleWorkflow do
  let(:job)          { described_class.create_job(*options).tap { |job| job.state = state } }
  let(:role_options) { {:role_name => 'role_name', :roles_path => 'path/role', :role_skip_facts => true } }
  let(:extra_vars)   { { arg1: "arg2" } }
  let(:options)      { [{"ENV" => "VAR"}, extra_vars, role_options] }
  let(:state)        { "waiting_to_start" }

  before do
    my_server = double("my_server", :guid => "guid1")
    allow(MiqServer).to receive(:my_server).and_return(my_server)
  end

  context ".create_job" do
    it "leaves job waiting to start" do
      expect(job.state).to eq("waiting_to_start")
    end
  end

  context "per_role" do
    let(:state) { "pre_execute" }
    context "ca_string given" do
      let(:extra_vars)   { { :arg1 => "res1", :ca_string => "my_ca" } }
      it "creates a tmp dir for certs in pre role" do
        job.signal(:pre_execute)
        expect(job.context[:ansible_cert_dir]).not_to be_nil
        expect(File.directory?(job.context[:ansible_cert_dir])).to be_truthy
      end

      it "creates a file and adds its path to the extra vars" do
        job.signal(:pre_execute)
        ec_file_path = job.options[:extra_vars][:engine_cafile]
        expect(ec_file_path).not_to be_nil
        data = File.read(ec_file_path)
        expect(data).to eq("my_ca")
        expect(job.reload.options[:extra_vars][:engine_cafile]).to eq(ec_file_path)
      end

      it "deletes the ca_string var" do
        job.signal(:pre_execute)
        expect(job.reload.options[:extra_vars][:ca_string]).to be_nil
      end
    end

    context "ca_string not given" do
      it "does not create a tmp dir for certs" do
        job.signal(:pre_execute)
        expect(job.context[:ansible_cert_dir]).to be_nil
      end
    end
  end
end
