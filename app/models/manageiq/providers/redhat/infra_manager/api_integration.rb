require 'openssl'
require 'ovirt_metrics'
require 'resolv'

module ManageIQ::Providers::Redhat::InfraManager::ApiIntegration
  extend ActiveSupport::Concern

  include SupportedApisMixin

  require 'ovirtsdk4'
  require 'ovirt'

  included do
    process_api_features_support
  end

  def supported_features
    @supported_features ||= supported_api_versions.collect { |version| self.class.api_features[version.to_s] }.flatten.uniq
  end

  def authentication_status_ok?(type = nil)
    return true if type == :ssh_keypair
    super
  end

  def use_graph_refresh?
    true
  end

  def apply_connection_options_defaults(options)
    {
      :id         => id,
      :scheme     => options[:scheme] || 'https',
      :server     => options[:ip] || address,
      :port       => options[:port] || port,
      :path       => options[:path] || '/ovirt-engine/api',
      :username   => options[:user] || authentication_userid(options[:auth_type]),
      :password   => options[:pass] || authentication_password(options[:auth_type]),
      :service    => options[:service] || "Service",
      :verify_ssl => default_endpoint.verify_ssl,
      :ca_certs   => default_endpoint.certificate_authority
    }
  end

  def connect(options = {})
    raise "no credentials defined" if missing_credentials?(options[:auth_type])
    version = options[:version] || highest_allowed_api_version
    unless options[:skip_supported_api_validation] || supports_the_api_version?(version)
      raise "version #{version} of the api is not supported by the provider"
    end

    # Prepare the options to call the method that creates the actual connection:
    connect_options = apply_connection_options_defaults(options)
    # Starting with version 4 of oVirt authentication doesn't work when using directly the IP address, it requires
    # the fully qualified host name, so if we received an IP address we try to convert it into the corresponding
    # host name:
    if self.class.resolve_ip_addresses?
      resolved = self.class.resolve_ip_address(connect_options[:server])
      if resolved != connect_options[:server]
        _log.info("IP address '#{connect_options[:server]}' has been resolved to host name '#{resolved}'.")
        default_endpoint.hostname = resolved
        connect_options[:server] = resolved
      end
    end

    # Create the underlying connection according to the version of the oVirt API requested by
    # the caller:
    connect_method = "raw_connect_v#{version}".to_sym
    connection = self.class.public_send(connect_method, connect_options)

    # Copy the API path to the endpoints table:
    default_endpoint.path = connect_options[:path]

    connection
  end

  def supports_port?
    true
  end

  def supported_auth_types
    %w(default metrics ssh_keypair)
  end

  def supports_authentication?(authtype)
    supported_auth_types.include?(authtype.to_s)
  end

  def rhevm_service
    @rhevm_service ||= connect(:service => "Service")
  end

  def rhevm_inventory(opts = {})
    connect_options = { :service => "Inventory" }
    connect_options[:version] = 3 if opts[:force_v3]
    @rhevm_inventory ||= connect(connect_options)
  end

  def ovirt_services(args = {})
    @ovirt_services ||= begin
                          ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Builder.new(self)
                                                                                           .build(args).new(:ems => self)
                        end
  end

  def disconnect(connection)
    self.class.disconnect(connection)
  rescue StandardError => error
    _log.error("Error while disconnecting #{error}")
  end

  def verify_credentials_for_rhevm(options = {})
    with_provider_connection(options) { |connection| connection.test(true) }
  rescue Exception => e
    self.class.handle_credentials_verification_error(e)
  end

  def rhevm_metrics_connect_options(options = {})
    metrics_hostname = connection_configuration_by_role('metrics')
                       .try(:endpoint)
                       .try(:hostname)
    server   = options[:hostname] || metrics_hostname || hostname
    username = options[:user] || authentication_userid(:metrics)
    password = options[:pass] || authentication_password(:metrics)
    database = options[:database] || history_database_name

    {
      :host     => server,
      :database => database,
      :username => username,
      :password => password
    }
  end

  def verify_credentials_for_rhevm_metrics(options = {})
    OvirtMetrics.connect(rhevm_metrics_connect_options(options))
    OvirtMetrics.connected?
  rescue StandardError => error
    raise self.class.adapt_metrics_error(error)
  ensure
    begin
      OvirtMetrics.disconnect
    rescue
      nil
    end
  end

  def authentications_to_validate
    at = [:default]
    at << :metrics if has_authentication_type?(:metrics)
    at
  end

  def verify_credentials(auth_type = nil, options = {})
    options[:skip_supported_api_validation] = true
    auth_type ||= 'default'
    case auth_type.to_s
    when 'default' then verify_credentials_for_rhevm(options)
    when 'metrics' then verify_credentials_for_rhevm_metrics(options)
    else;          raise "Invalid Authentication Type: #{auth_type.inspect}"
    end
  end

  def history_database_name
    connection_configurations.try(:metrics).try(:endpoint).try(:path) || self.class.default_history_database_name
  end

  # Adding disks is supported only by API version 4.0
  def with_disk_attachments_service(vm)
    with_version4_vm_service(vm) do |service|
      disk_service = service.disk_attachments_service
      yield disk_service
    end
  end

  def with_version4_vm_service(vm)
    connection = connect(:version => 4)
    service = connection.system_service.vms_service.vm_service(vm.uid_ems)
    yield service
  end

  def use_ovirt_sdk?
    true
  end

  class_methods do
    def disconnect(connection)
      if connection.respond_to?(:disconnect)
        connection.disconnect
      end
    end

    def api3_supported_features
      []
    end

    def api4_supported_features
      [
        :migrate,
        :quick_stats,
        :reconfigure_disks,
        :snapshots,
        :publish
      ]
    end

    def api_features
      { "3" => api3_supported_features, "4" => api4_supported_features }
    end

    def process_api_features_support
      all_features = api_features.values.flatten.uniq
      all_features.each do |feature|
        supports feature do
          unless supported_features.include?(feature)
            unsupported_reason_add(feature, _("This feature is not supported by the api version of the provider"))
          end
        end
      end
    end

    def rethrow_as_a_miq_error(ovirt_sdk_4_error)
      case ovirt_sdk_4_error.message
      when /The username or password is incorrect/
        raise MiqException::MiqInvalidCredentialsError, "Incorrect user name or password."
      when /Couldn't connect to server/, /Couldn't resolve host name/
        raise MiqException::MiqUnreachableError, $ERROR_INFO
      else
        _log.error("Error while verifying credentials #{$ERROR_INFO}")
        raise MiqException::MiqEVMLoginError, $ERROR_INFO
      end
    end

    def handle_credentials_verification_error(e)
      case e
      when SocketError, Errno::EHOSTUNREACH, Errno::ENETUNREACH
        _log.warn($ERROR_INFO)
        raise MiqException::MiqUnreachableError, $ERROR_INFO
      when MiqException::MiqUnreachableError
        raise e
      when RestClient::Unauthorized
        raise MiqException::MiqInvalidCredentialsError, "Incorrect user name or password."
      when OvirtSDK4::Error
        rethrow_as_a_miq_error(e)
      else
        _log.error("Error while verifying credentials #{$ERROR_INFO}")
        raise MiqException::MiqEVMLoginError, $ERROR_INFO
      end
    end

    #
    # This method is called only when the UI button to verify the connection details is clicked. It isn't used create
    # the connections actually used by the provider.
    #
    # Note that the protocol (HTTP or HTTPS) and the version of the API are *not* options of this method, if they are
    # provided they will be silently ignored.
    #
    # @param opts [Hash] A hash containing the connection details and the credentials.
    # @option opts [String] :username The name of the API user.
    # @option opts [String] :password The password of the API user.
    # @option opts [String] :server The host name or IP address of the API server.
    # @option opts [Integer] :port ('443') The port number of the API server.
    # @option opts [Integer] :verify_ssl ('1') A numeric flag indicating if the TLS certificates of the API server
    #   should be checked. Value `0` indicates that the should not be checked, value `1` indicates that they should
    #   be checked.
    # @option opts [String] :ca_certs The custom trusted CA certificates used to check the TLS certificates of the
    #   API server, in PEM format. A blank or nil value means that no custom CA certificates should be used.
    # @option opts [String] :metrics_userid The name of the metrics database user.
    # @option opts [String] :metrics_password The password of the metrics database user.
    # @options opts [String] :metrics_server The host name or IP address of the metrics database server.
    # @options opts [Integer] :metrics_port ('5432') The port number of the metrics database server.
    # @options opts [String] :metrics_database The name of the metrics database.
    # @return [Boolean] Returns `true` if the connection details and credentials are valid, or `false` otherwise.
    #
    def raw_connect(opts = {})
      check_connect_api(opts)
      check_connect_metrics(opts)
    rescue Exception => e
      handle_credentials_verification_error(e)
    end

    #
    # Checks the API connection details.
    #
    # @api private
    #
    def check_connect_api(opts = {})
      # Get options and assign default values:
      username = opts[:username]
      password = opts[:password]
      server = opts[:server]
      port = opts[:port] || 443
      verify_ssl = opts[:verify_ssl] || 1
      ca_certs = opts[:ca_certs]

      # Decrypt the password:
      password = ManageIQ::Password.try_decrypt(password)

      # Starting with version 4 of oVirt authentication doesn't work when using directly the IP address, it requires
      # the fully qualified host name, so if we received an IP address we try to convert it into the corresponding
      # host name:
      resolved = server
      if resolve_ip_addresses?
        resolved = resolve_ip_address(server)
        if resolved != server
          _log.info("IP address '#{server}' has been resolved to host name '#{resolved}'.")
        end
      end

      # Build the options that will be used to call the methods that create the connection with specific versions
      # of the API:
      opts = {
        :username   => username,
        :password   => password,
        :server     => resolved,
        :port       => port,
        :verify_ssl => verify_ssl,
        :ca_certs   => ca_certs,
        :service    => 'Inventory' # This is needed only for version 3 of the API.
      }

      # Try to verify the details using version 4 of the API. If this succeeds or fails with an authentication
      # exception, then we don't need to do anything else. Note that the connection should not be closed, because
      # that is handled by the `ConnectionManager` class.
      begin
        connection = raw_connect_v4(opts)
        connection.test(:raise_exception => true)
        return true
      rescue OvirtSDK4::Error => error
        raise error if /error.*sso/i =~ error.message
      end

      # Try to verify the details using version 3 of the API.
      begin
        connection = raw_connect_v3(opts)
        connection.api
      ensure
        disconnect(connection)
      end
      true
    end

    #
    # Checks the metrics connection details.
    #
    # @api private
    #
    def check_connect_metrics(opts = {})
      # Get the options and assign defaults:
      username = opts[:metrics_username]
      password = opts[:metrics_password]
      server = opts[:metrics_server]
      port = opts[:metrics_port] || 5432
      database = opts[:metrics_database] || default_history_database_name

      # Metrics are optional, so we should only check the details if the server has been specified:
      return true if server.blank?

      # Decrypt the password:
      password = ManageIQ::Password.try_decrypt(password)

      # Build the options that will be used to call the methods that checks that the metrics connection can
      # be created:
      opts = {
        :username => username,
        :password => password,
        :host     => server,
        :port     => port,
        :database => database
      }
      begin
        OvirtMetrics.connect(opts)
        OvirtMetrics.connected?
      rescue StandardError => error
        raise adapt_metrics_error(error)
      ensure
        begin
          OvirtMetrics.disconnect
        rescue
          nil
        end
      end
    end

    # Connect to the engine using version 4 of the API and the `ovirt-engine-sdk` gem.
    def raw_connect_v4(options = {})
      require 'ovirtsdk4'

      # Get the timeouts from the configuration:
      read_timeout, open_timeout = ems_timeouts(:ems_redhat, options[:service])

      # The constructor of the SDK expects a list of certificates, but that list can't be empty, or contain only 'nil'
      # values, so we need to check the value passed and make a list only if it won't be empty. If it will be empty then
      # we should just pass 'nil'.
      ca_certs = options[:ca_certs]
      ca_certs = nil if ca_certs.blank?
      ca_certs = [ca_certs] if ca_certs

      url = URI::Generic.build(
        :scheme => 'https',
        :host   => options[:server],
        :port   => options[:port],
        :path   => '/ovirt-engine/api'
      )

      ManageIQ::Providers::Redhat::ConnectionManager.instance.get(
        options[:id],
        :url             => url.to_s,
        :username        => options[:username],
        :password        => options[:password],
        :timeout         => read_timeout,
        :connect_timeout => open_timeout,
        :insecure        => options[:verify_ssl] == OpenSSL::SSL::VERIFY_NONE,
        :ca_certs        => ca_certs,
        :log             => $rhevm_log,
        :connections     => options[:connections] || ::Settings.ems_refresh.rhevm.connections,
        :pipeline        => options[:pipeline] || ::Settings.ems_refresh.rhevm.pipeline
      )
    end

    # Connect to the engine using version 3 of the API and the `ovirt` gem.
    def raw_connect_v3(options = {})
      require 'ovirt'
      require 'manageiq/providers/ovirt/legacy/inventory'
      Ovirt.logger = $rhevm_log

      # If 'ca_certs' is an empty string then the 'ovirt' gem will trust nothing, but we want it to trust the system CA
      # certificates. To get that behaviour we need to pass 'nil' instead of the empty string.
      ca_certs = options[:ca_certs]
      ca_certs = nil if ca_certs.blank?

      params = {
        :server     => options[:server],
        :port       => options[:port].presence && options[:port].to_i,
        :path       => '/ovirt-engine/api',
        :username   => options[:username],
        :password   => options[:password],
        :verify_ssl => options[:verify_ssl],
        :ca_certs   => ca_certs
      }

      read_timeout, open_timeout = ems_timeouts(:ems_redhat, options[:service])
      params[:timeout]      = read_timeout if read_timeout
      params[:open_timeout] = open_timeout if open_timeout
      const = options[:service] == "Inventory" ? ManageIQ::Providers::Ovirt::Legacy::Inventory : Ovirt.const_get(options[:service])
      conn = const.new(params)
      OvirtConnectionDecorator.new(conn)
    end

    class OvirtConnectionDecorator < SimpleDelegator
      def test(_raise_exceptions)
        api
      rescue Ovirt::MissingResourceError, URI::InvalidURIError
        raise MiqException::MiqUnreachableError, "Invalid URI specified for the server."
      end
    end

    def default_history_database_name
      OvirtMetrics::DEFAULT_HISTORY_DATABASE_NAME
    end

    # Calculates an "ems_ref" from the "href" attribute provided by the oVirt REST API, removing the
    # "/ovirt-engine/" prefix, as for historic reasons the "ems_ref" stored in the database does not
    # contain it, it only contains the "/api" prefix which was used by older versions of the engine.
    def make_ems_ref(href)
      href && href.sub(%r{^/ovirt-engine/}, '/')
    end

    def extract_ems_ref_id(href)
      href && href.split("/").last
    end

    #
    # Checks if IP address to host name resolving is enabled.
    #
    # @return [Boolean] `true` if host name resolving is enabled in the configuration, `false` otherwise.
    #
    # @api private
    #
    def resolve_ip_addresses?
      ::Settings.ems.ems_redhat.resolve_ip_addresses
    end

    #
    # Tries to convert the given IP address into a host name, doing a reverse DNS lookup if needed. If it
    # isn't possible to find the host name the original IP address will be returned, and a warning will be
    # written to the log.
    #
    # @param address [String] The IP address.
    # @return [String] The host name.
    #
    # @api private
    #
    def resolve_ip_address(address)
      # Don't try to resolve unless the string is really an IP address and not a host name:
      return address unless address =~ Resolv::IPv4::Regex || address =~ Resolv::IPv6::Regex

      # Try to do a reverse resolve of the address to find the host name, using the default resolver, which
      # means first using the local hosts file and then DNS:
      begin
        Resolv.getname(address)
      rescue Resolv::ResolvError
        _log.warn(
          "Can't find fully qualified host name for IP address '#{address}', will use the IP address " \
          "directly."
        )
        address
      end
    end

    #
    # Adapts the given error raised by the metrics connection into the exceptions that the ManageIQ core expects.
    #
    # @param error [Exception] The exception generated by the attempt to connect to the metrics database.
    # @return [Exception] The exception that the ManageIQ expects.
    #
    # @api private
    # rhevm_metrics_connect_options
    def adapt_metrics_error(error)
      case error
      when PG::Error
        message = error.message
        message = error.message[6..-1] if message.starts_with?('FATAL:')
        message = message.strip
        _log.warn("#{error.class.name}: #{message}")
        MiqException::MiqEVMLoginError.new(message)
      else
        MiqException::MiqEVMLoginError.new(error.to_s)
      end
    end
  end
end
