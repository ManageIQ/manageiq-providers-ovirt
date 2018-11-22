class ManageIQ::Providers::Redhat::AnsibleRoleWorkflow < ManageIQ::Providers::AnsibleRoleWorkflow
  def pre_role
    handle_ca_string
    super
  end

  def post_playback
    FileUtils.remove_entry(context[:ansible_cert_dir]) if context[:ansible_cert_dir]
    super
  end

  def handle_ca_string
    ca_string = options[:extra_vars] && options[:extra_vars].delete(:ca_string)
    return if ca_string.nil?
    context[:ansible_cert_dir] = Dir.mktmpdir("rhv_ansible_workflow")
    options[:extra_vars][:engine_cafile] = create_cert_file(ca_string)
    save
  end

  def create_cert_file(ca_string)
    local_filename = File.join(context[:ansible_cert_dir], "ca_#{SecureRandom.hex}")
    File.open(local_filename, 'w') {|f| f.write(ca_string) }
    local_filename
  end

  alias start pre_role
end
