class ManageIQ::Providers::Redhat::InfraManager::EmsCluster < ::EmsCluster
  def upgrade(options = {})
    role_options = {:role_name => "oVirt.cluster-upgrade"}
    job = ManageIQ::Providers::AnsibleRoleWorkflow.create_job({}, extra_vars_for_upgrade(options), role_options)
    job.signal(:start)
    job.miq_task
  end

  private

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
end
