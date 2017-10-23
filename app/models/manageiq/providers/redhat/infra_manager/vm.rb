require 'nokogiri'
require 'openssl'
require 'ovirtsdk4'
require 'uri'

class ManageIQ::Providers::Redhat::InfraManager::Vm < ManageIQ::Providers::InfraManager::Vm
  include_concern 'Operations'
  include_concern 'RemoteConsole'
  include_concern 'Reconfigure'
  include_concern 'ManageIQ::Providers::Redhat::InfraManager::VmOrTemplateShared'

  supports :migrate do
    if blank? || orphaned? || archived?
      unsupported_reason_add(:migrate, "Migrate operation in not supported.")
    elsif !ext_management_system.supports_migrate?
      unsupported_reason_add(:migrate, 'RHV API version does not support migrate')
    end
  end

  supports :reconfigure_disks do
    if storage.blank?
      unsupported_reason_add(:reconfigure_disks, _('storage is missing'))
    elsif ext_management_system.blank?
      unsupported_reason_add(:reconfigure_disks, _('The virtual machine is not associated with a provider'))
    elsif !ext_management_system.supports_reconfigure_disks?
      unsupported_reason_add(:reconfigure_disks, _('The provider does not support reconfigure disks'))
    end
  end

  supports_not :reset
  supports :publish do
    if blank? || orphaned? || archived?
      unsupported_reason_add(:publish, _('Publish operation in not supported'))
    elsif ext_management_system.blank?
      unsupported_reason_add(:publish, _('The virtual machine is not associated with a provider'))
    elsif !ext_management_system.supports_publish?
      unsupported_reason_add(:publish, _('This feature is not supported by the api version of the provider'))
    elsif power_state != "off"
      unsupported_reason_add(:publish, _('The virtual machine must be down'))
    end
  end

  POWER_STATES = {
    'up'        => 'on',
    'down'      => 'off',
    'suspended' => 'suspended',
  }.freeze

  def provider_object(connection = nil)
    ovirt_services_class = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Builder
                           .build_from_ems_or_connection(:ems => ext_management_system, :connection => connection)
    ovirt_services_class.new(:ems => ext_management_system).get_vm_proxy(self, connection)
  end

  def scan_via_ems?
    true
  end

  def parent_cluster
    rp = parent_resource_pool
    rp && rp.detect_ancestor(:of_type => "EmsCluster").first
  end
  alias owning_cluster parent_cluster
  alias ems_cluster parent_cluster

  def disconnect_storage(_s = nil)
    return unless active?

    vm_storages = ([storage] + storages).compact.uniq
    return if vm_storages.empty?

    vm_disks = collect_disks
    storage = vm_disks.blank? ? nil : vm_storages.select { |store| !vm_disks.include?(store.ems_ref) }

    super(storage)
  end

  def collect_disks
    return [] if hardware.nil?
    disks = hardware.disks.map do |disk|
      unless disk.storage.nil?
        "#{disk.storage.ems_ref}/disks/#{disk.filename}"
      end
    end
    ext_management_system.ovirt_services.collect_disks_by_hrefs(disks.compact)
  end

  def exists_on_provider?
    return false unless ext_management_system
    ext_management_system.ovirt_services.vm_exists_on_provider?(self)
  end

  def disconnect_inv
    disconnect_storage

    super
  end

  #
  # UI Button Validation Methods
  #

  def has_required_host?
    true
  end

  def self.calculate_power_state(raw_power_state)
    POWER_STATES[raw_power_state] || super
  end

  #
  # This method is executed in the UI worker. It adds to the queue a task to retrieve the
  # URL of the oVirt UI for this virtual machine.
  #
  # @return [Integer] The identifier of the task.
  #
  def queue_generate_ui_url
    # Create the task options:
    task_options = {
      action: "Generate oVirt UI URL for VM '#{name}'"
    }

    # Create the queue options:
    queue_options = {
      class_name: self.class.name,
      instance_id: id,
      method_name: 'generate_ui_url',
      priority: MiqQueue::HIGH_PRIORITY,
      role: 'ems_operations',
      zone: my_zone,
      args: []
    }

    # Add the task to the queue and return the identifier:
    MiqTask.generic_action_with_callback(task_options, queue_options)
  end

  #
  # This method is executed in the provider worker. It contacts the calculates oVirt URL using the
  # credentials of the provider.
  #
  # @return [String] The oVirt URL.
  #
  def generate_ui_url
    # Get the reference to the EMS:
    ems = ext_management_system

    # Calculate the target URL:
    endpoint = ems.default_endpoint
    target = URI::HTTPS.build(
      host: endpoint.hostname,
      port: endpoint.port,
      path: '/ovirt-engine/webadmin/',
    ).to_s

    # Get the credentials of the provider:
    user = ems.authentication_userid(:default)
    password = ems.authentication_password(:default)

    # Split the authentication user into user name and profile, assuming that the profile is the
    # text after the last at sign:
    at = user.rindex('@')
    profile = ''
    unless at.nil?
      profile = user[(at + 1)..-1]
      user = user[0..at - 1]
    end

    # Create the HTTP client:
    insecure = endpoint.verify_ssl == OpenSSL::SSL::VERIFY_NONE,
    ca_certs = endpoint.certificate_authority
    ca_certs = nil if ca_certs.blank?
    ca_certs = [ca_certs] if ca_certs
    client = OvirtSDK4::HttpClient.new(
      insecure: insecure,
      ca_certs: ca_certs,
      cookies: true,
      log: $rhevm_log
    )

    # Send the initial request, and follow the potentially multiple redirects that the server and the
    # SSO service will ask us to do:
    url = target
    request = nil
    response = nil
    loop do
      request = OvirtSDK4::HttpRequest.new
      request.method = :GET
      request.url = url
      client.send(request)
      response = client.wait(request)
      break if response.code != 302
      url = response.headers['location']
    end

    # When we finally land in the HTML page that contains the authentication form, we need to parse the
    # HTML page and extract the action:
    page = Nokogiri::HTML(response.body)
    action = page.xpath('//form/@action').first

    # Post the form with the credentials:
    url = URI(url)
    url.path = action
    url = url.to_s
    request = OvirtSDK4::HttpRequest.new
    request.method = :POST
    request.url = url
    request.headers = {
      'content-type': 'application/x-www-form-urlencoded',
    }
    request.body = URI.encode_www_form(
      username: user,
      password: password,
      profile: profile
    )
    client.send(request)
    response = client.wait(request)

    # We need now to follow the potentially multiple redirects that the SSO service will ask to do, till
    # we are redirected to the URL that we originally requested. When that happens we know that the
    # previous URL had all the information to automatically log-in to the application.
    previous = nil
    loop do
      previous = url
      url = response.headers['location']
      break if url == target
      request = OvirtSDK4::HttpRequest.new
      request.method = :GET
      request.url = url
      client.send(request)
      response = client.wait(request)
    end

    # Close the HTTP client:
    client.close

    # Return the URL:
    previous
  end
end
