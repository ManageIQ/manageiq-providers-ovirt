require 'manageiq/providers/ovirt/legacy/event_monitor'

class ManageIQ::Providers::Redhat::InfraManager::EventCatcher::Runner < ManageIQ::Providers::BaseManager::EventCatcher::Runner
  def event_monitor_handle
    @event_monitor_handle ||= ManageIQ::Providers::Ovirt::Legacy::EventMonitor.new(:ems => @ems)
  end

  def reset_event_monitor_handle
    @event_monitor_handle = nil
  end

  def stop_event_monitor
    @event_monitor_handle.stop unless @event_monitor_handle.nil?
  rescue Exception => err
    _log.warn("#{log_prefix} Event Monitor Stop errored because [#{err.message}]")
    _log.warn("#{log_prefix} Error details: [#{err.details}]")
    _log.log_backtrace(err)
  ensure
    reset_event_monitor_handle
  end

  def monitor_events
    event_monitor_handle.start
    event_monitor_handle.each_batch do |events|
      event_monitor_running
      @queue.enq events
      sleep_poll_normal
    end
  ensure
    reset_event_monitor_handle
  end

  def queue_event(event)
    _log.info "#{log_prefix} Caught event [#{event.name}]"
    parser = ManageIQ::Providers::Redhat::InfraManager::EventParsing::Builder.new(@ems).build
    event_hash = parser.event_to_hash(event, @cfg[:ems_id])
    EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
  end

  def filtered?(event)
    filtered_events.include?(event.name)
  end

  def event_dedup_key(event)
    # referred to https://www.rubydoc.info/gems/ovirt-engine-sdk/4.0.0/OvirtSDK4/EventReader
    {
      :description    => event.description,
      :code           => event.code,
      :correlation_id => event.correlation_id,
      :custom_id      => event.custom_id,
      :origin         => event.origin,
      :severity       => event.severity,
      :cluster        => event.cluster,
      :data_center    => event.data_center,
      :host           => event.host,
      :storage_domain => event.storage_domain,
      :template       => event.template,
      :user           => event.user,
      :vm             => event.vm
    }
  end

  alias_method :event_dedup_descriptor, :event_dedup_key
end
