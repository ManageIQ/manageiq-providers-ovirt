class ManageIQ::Providers::Redhat::InfraManager::FuturesCollector
  attr_reader :keyed_futures_queue, :keyed_requests_queue, :parallel_processing_capacity
  attr_accessor :res_hash

  include Vmdb::Logging

  DEFAULT_PARALLEL_PROCESSING_CAPACITY = 2000

  def self.process_keyed_requests_queue(keyed_requests_queue, batch_size = nil)
    collector = new(:batch_size => batch_size)
    collector.queue_keyed_request_tasks(keyed_requests_queue)
    collector.process_queues
  end

  def initialize(args)
    @keyed_futures_queue = []
    @keyed_requests_queue = []
    @parallel_processing_capacity = args[:batch_size] || DEFAULT_PARALLEL_PROCESSING_CAPACITY
    @res_hash = {}
  end

  def queue_keyed_request_tasks(keyed_request_tasks)
    @keyed_requests_queue += keyed_request_tasks.collect { |kv| KeyedValue.from_hash(kv) }
  end

  def process_queues
    process_keyed_requests_queue
    while tasks_present?
      process_keyed_futures_queue if keyed_futures_queue.present?
      process_keyed_requests_queue
    end
    res_hash
  end

  def process_keyed_futures_queue
    while keyed_futures_queue.present?
      keyed_future = keyed_futures_queue.shift
      res_hash[keyed_future.key] = keyed_future.value.wait
      process_one_keyed_request if keyed_requests_queue.present?
    end
  end

  def process_one_keyed_request
    return if keyed_requests_queue.empty?
    keyed_request = keyed_requests_queue.shift
    keyed_futures_queue << KeyedValue.from_key_value(keyed_request.key, keyed_request.value.call)
  rescue => e
    _log.warn("could not create future out of #{keyed_request.inspect}, due to: #{e.message}")
  end

  def process_keyed_requests_queue
    parallel_processing_capacity.times do
      return if keyed_requests_queue.empty?
      process_one_keyed_request
    end
  end

  def tasks_present?
    keyed_futures_queue.present? || keyed_requests_queue.present?
  end

  class KeyedValue
    attr_reader :key, :value
    def initialize(key_value_hash)
      @key, @value = key_value_hash.first
    end

    def self.from_key_value(key, value)
      new(key => value)
    end

    def self.from_hash(h)
      new(h)
    end
  end
end
