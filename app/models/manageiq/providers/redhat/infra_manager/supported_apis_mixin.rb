module ManageIQ::Providers::Redhat::InfraManager::SupportedApisMixin
  def supported_api_versions
    reload_if_api_version_available_in_db if api_version.blank?
    return supported_api_versions_from_sdk(probe_args) if api_version.blank?
    supported_api_versions_from_db
  end

  def reload_if_api_version_available_in_db
    reload if ExtManagementSystem.where(:id => id).select(:api_version).take&.api_version
  end

  def highest_supported_api_version
    supported_api_versions.sort.last || '3'
  end

  def highest_allowed_api_version
    return '3' unless use_ovirt_sdk?
    highest_supported_api_version
  end

  # This method is a result of api_version in the db not actually being the api_version
  # it is actually the product version based on which we infer the api version.
  # In the future I hope there will be a separate field created.
  def supported_api_versions_from_db
    key = product_version_to_api_version_regexps.keys.detect { |k| api_version =~ Regexp.new(k.to_s, Regexp::EXTENDED) }
    product_version_to_api_version_regexps[key] || []
  end

  def product_version_to_api_version_regexps
    return @parsed_regex_settings if @parsed_regex_settings
    @parsed_regex_settings = {}
    version_regex_settings = Settings::ems::ems_redhat.product_version_to_api_version_regexps
    version_regex_settings.keys.each do |k|
      @parsed_regex_settings[k] = version_regex_settings[k].to_s.split(' ').collect(&:to_s)
    end
    @parsed_regex_settings
  end

  def supports_the_api_version?(version)
    if supported_api_versions.empty?
      raise MiqException::MiqUnreachableError, "Not able to connect to the server."
    end
    supported_api_versions.map(&:to_s).include?(version.to_s)
  end

  def supported_api_versions_from_sdk(args)
    probe_args = { :host => args[:hostname], :port => args[:port], :username => args[:username], :password => args[:password], :insecure => true }
    probe_results = OvirtSDK4::Probe.probe(probe_args)
    probe_results&.map(&:version)
  rescue => error
    # Note that errors when trying to find the supported API versions are perfectly normal, in particular authorization
    # errors are expected, as in many situations, for example during discovery, the user name and the password aren't
    # yet known. In these situations we *must* return an empty array, to indicate to the caller that it wasn't possible
    # to determine the supported API versions.
    _log.info("Can't determine the API versions supported by the server: #{error}")
    []
  end

  def probe_args
    {
      :username => authentication_userid(:basic),
      :password => authentication_password(:basic),
      :hostname => hostname,
      :port     => port
    }
  end
end
