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
  rescue SignalException => e
    if e.message == "SIGTERM"
      _log.info("#{self.class.name}##{__method__}: ignoring SIGTERM")
    else
      raise
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
end
