module ManageIQ
  module Providers
    module Ovirt
      module Legacy
        class EventMonitor
          def initialize(options = {})
            @ems = options[:ems]
          end

          def event_fetcher
            @event_fetcher ||= @ems.ovirt_services.event_fetcher
          end

          def start
            @since          = nil
            @event_fetcher  = nil
            @monitor_events = true
          end

          def stop
            @monitor_events = false
          end

          def each_batch
            while @monitor_events
              # grab only the most recent event if this is the first time through
              query_options = @since ? {:since => @since} : {:max => 1}
              events = event_fetcher.events(query_options).sort_by { |e| e.id.to_i }
              @since = events.last.id.to_i unless events.empty?

              yield events
            end
          end

          def each
            each_batch do |events|
              events.each { |e| yield e }
            end
          end
        end
      end
    end
  end
end
