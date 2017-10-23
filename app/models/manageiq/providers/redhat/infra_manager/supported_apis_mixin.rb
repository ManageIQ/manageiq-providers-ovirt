module ManageIQ::Providers::Redhat::InfraManager::SupportedApisMixin
  def supported_api_versions(use_queue: false)
    return supported_api_versions_from_cache(use_queue: use_queue) if api_version.blank?
    supported_api_versions_from_db
  end

  DEFAULT_PRODUCT_VERSION_TO_API_VERSION_REGEX_HASH = {
    '3\.\d+\.?\d*' => %w(3),
    '4\.\d+\.?\d*' => %w(3 4)
  }

  # This method is a result of api_version in the db not actually being the api_version
  # it is actually the product version based on which we infer the api version.
  # In the future I hope there will be a separate field created.
  def supported_api_versions_from_db
    product_v_to_api_v_hash = DEFAULT_PRODUCT_VERSION_TO_API_VERSION_REGEX_HASH ||
      Setting::ems::ems_redhat.default_product_version_to_api_version_regex_hash
    key = product_v_to_api_v_hash.keys.detect {|k| api_version =~ Regexp.new(k, Regexp::EXTENDED)}
    product_v_to_api_v_hash[key]
  end

  def supported_api_versions_from_cache(use_queue:)
    cacher = Cacher.new(cache_key)
    current_cache_val = cacher.read
    force = current_cache_val.blank?
    cacher.fetch_fresh(last_refresh_date, :force => force) { supported_api_versions_from_sdk(use_queue) }
  end

  def supported_api_versions_from_sdk(use_queue)
    return supported_api_versions_from_sdk_through_queue if use_queue
    supported_api_versions_from_sdk_raw
  end

  def supported_api_versions_from_sdk_raw
    self.class::SupportedApisMixin.supported_api_versions_from_sdk_raw(probe_args)
  end

  def self.supported_api_versions_from_sdk_raw(args)
    probe_args = { :host => args[:hostname], :port => args[:port], :username => args[:username], :password => args[:password], :insecure => true }
    probe_results = OvirtSDK4::Probe.probe(probe_args)
    probe_results.map(&:version) if probe_results
  rescue => error
    _log.error("Error while probing supported api versions #{error}")
    raise
  end

  def probe_args
    {
      username: authentication_userid(:basic),
      password: authentication_password(:basic),
      hostname: hostname,
      port: port
    }
  end

  def supported_api_versions_from_sdk_through_queue
    task_options = {
      :action => "Probe supported api versions"
    }

    queue_options = {
      :task_id     => nil,
      :class_name  => "#{self.class.name}::SupportedApisMixin",
      :method_name => 'supported_api_versions_from_sdk_raw',
      :zone        => zone,
      :args        => probe_args
    }

    task_id = MiqTask.generic_action_with_callback(task_options, queue_options)
    completed_task = MiqTask.wait_for_taskid(task_id)
    if completed_task.status != MiqTask::STATUS_OK
      _log.error("Failed to fetch supported api versions for host #{hostname}, message: #{completed_task.message}")
      return []
    end
    completed_task.task_results
  end

  def cache_key
    "REDHAT_EMS_CACHE_KEY_#{id}"
  end

  class Cacher
    attr_reader :key

    def initialize(key)
      @key = key
    end

    def fetch_fresh(last_refresh_time, options)
      force = options[:force] || stale_cache?(last_refresh_time)
      res = Rails.cache.fetch(key, :force => force) { build_entry { yield } }
      res[:value]
    end

    def read
      res = Rails.cache.read(key)
      res && res[:value]
    end

    private

    def build_entry
      {:created_at => Time.now.utc, :value => yield}
    end

    def stale_cache?(last_refresh_time)
      current_val = Rails.cache.read(key)
      return true unless current_val && current_val[:created_at] && last_refresh_time
      last_refresh_time > current_val[:created_at]
    end
  end
end
