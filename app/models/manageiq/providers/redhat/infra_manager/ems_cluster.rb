class ManageIQ::Providers::Redhat::InfraManager::EmsCluster < ManageIQ::Providers::InfraManager::EmsCluster
  def upgrade(options = {})
    role_options = {:role_name => "oVirt.cluster-upgrade"}
    job = ManageIQ::Providers::AnsibleRoleWorkflow.create_job({}, extra_vars_for_upgrade(options), role_options, :hook_object => cert_file_creator)
    job.signal(:start)
    job.miq_task
  end

  private

  def cert_file_creator
    cert = ext_management_system.default_endpoint.certificate_authority
    return nil unless cert
    CertificateFileCreator.new(cert)
  end

  def extra_vars_for_upgrade(options = {})
    connect_options = ext_management_system.apply_connection_options_defaults(options)

    url = URI::Generic.build(
      :scheme => connect_options[:scheme],
      :host   => connect_options[:server],
      :port   => connect_options[:port],
      :path   => connect_options[:path]
    ).to_s

    {
      :engine_url      => url,
      :engine_user     => connect_options[:username],
      :engine_password => connect_options[:password],
      :cluster_name    => name,
      :hostname        => "localhost"
    }
  end

  class CertificateFileCreator
    attr_accessor :cert
    def initialize(cert)
      @cert = cert
    end

    def after_dir_create(base_dir, _env_vars, extra_vars, _ansible_runner_method, _playbook_or_role_args)
      local_filename = File.join(base_dir, "ca_#{SecureRandom.hex}")
      File.open(local_filename, 'w') {|f| f.write(cert) }
      extra_vars[:engine_cafile] = local_filename
    end
  end
end
