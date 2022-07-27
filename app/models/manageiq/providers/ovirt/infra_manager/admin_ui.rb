module ManageIQ::Providers::Ovirt::InfraManager::AdminUI
  extend ActiveSupport::Concern

  require 'openssl'
  require 'ovirtsdk4'
  require 'uri'
  require 'json'

  def queue_generate_admin_ui_url
    task_opts = {
      :action => 'Generate oVirt Admin UI URL for EMS'
    }

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => 'generate_admin_ui_url',
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => []
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def generate_admin_ui_url
    $rhevm_log.info("Generating oVirt Admin UI URL for EMS with identifier '#{id}'.")

    # Get the credentials of the provider:
    user = authentication_userid(:default)
    password = authentication_password(:default)

    # Get the timeouts from the configuration:
    read_timeout, open_timeout = self.class.ems_timeouts(:ems_ovirt, "Service")

    # Create the HTTP client:
    insecure = default_endpoint.verify_ssl == OpenSSL::SSL::VERIFY_NONE,
    ca_certs = default_endpoint.certificate_authority
    ca_certs = nil if ca_certs.blank?
    ca_certs = [ca_certs] if ca_certs
    client = OvirtSDK4::HttpClient.new(
      :insecure        => insecure,
      :ca_certs        => ca_certs,
      :log             => $rhevm_log,
      :timeout         => read_timeout,
      :connect_timeout => open_timeout
    )

    # Request new SSO token using the provider credentials:
    request = OvirtSDK4::HttpRequest.new
    request.method = :POST
    request.url = URI::HTTPS.build(
      :host => default_endpoint.hostname,
      :port => default_endpoint.port,
      :path => '/ovirt-engine/sso/oauth/token'
    ).to_s
    request.headers = {
      'Accept'       => 'application/json',
      'Content-Type' => 'application/x-www-form-urlencoded',
      'User-Agent'   => "manageiq-providers-ovirt/#{ManageIQ::Providers::Ovirt::VERSION}"
    }
    request.body = URI.encode_www_form(
      :grant_type => 'password',
      :username   => user,
      :password   => password,
      :scope      => 'ovirt-app-admin ovirt-app-portal'
    )
    client.send(request)
    response = client.wait(request)

    # Close the HTTP client:
    client.close

    # Extract the SSO token, return nil in case of error:
    if response.kind_of?(OvirtSDK4::Error) || response.code != 200
      $rhevm_log.warn("Failed to obtain SSO token from oVirt Engine.")
      $rhevm_log.warn(response.message) if response.kind_of?(OvirtSDK4::Error)
      return nil
    end
    sso_token = JSON.parse(response.body)['access_token']

    # Generate URL to access oVirt Admin UI using the SSO token:
    app_url = URI::HTTPS.build(
      :host => default_endpoint.hostname,
      :port => default_endpoint.port,
      :path => '/ovirt-engine/webadmin'
    ).to_s
    access_url = URI::HTTPS.build(
      :host  => default_endpoint.hostname,
      :port  => default_endpoint.port,
      :path  => '/ovirt-engine/webadmin/sso/login',
      :query => URI.encode_www_form(
        :sso_token => sso_token,
        :app_url   => app_url
      )
    ).to_s

    # Return the URL:
    access_url
  end
end
