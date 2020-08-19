class ManageIQ::Providers::Redhat::InfraManager::Vm
  module RemoteConsole
    def console_supported?(type)
      return true if type.upcase == 'NATIVE'

      %w[SPICE VNC].include?(type.upcase) && html5_console_enabled?
    end

    def validate_remote_console_acquire_ticket(protocol, options = {})
      raise(MiqException::RemoteConsoleNotSupportedError,
            "#{protocol} protocol not enabled for this vm") unless protocol.to_sym == :html5

      raise(MiqException::RemoteConsoleNotSupportedError,
            "Html5 console is disabled by default, check settings to enable it") unless html5_console_enabled?

      raise(MiqException::RemoteConsoleNotSupportedError,
            "#{protocol} remote console requires the vm to be registered with a management system.") if ext_management_system.nil?

      options[:check_if_running] = true unless options.key?(:check_if_running)
      raise(MiqException::RemoteConsoleNotSupportedError,
            "#{protocol} remote console requires the vm to be running.") if options[:check_if_running] && state != "on"
    end

    def remote_console_acquire_ticket(userid, originating_server, console_type)
      validate_remote_console_acquire_ticket(console_type)
      ext_management_system.ovirt_services.remote_console_acquire_ticket(self, userid, originating_server)
    end

    def remote_console_acquire_ticket_queue(protocol, userid)
      task_opts = {
        :action => "acquiring Vm #{name} #{protocol.to_s.upcase} remote console ticket for user #{userid}",
        :userid => userid
      }

      queue_opts = {
        :class_name  => self.class.name,
        :instance_id => id,
        :method_name => 'remote_console_acquire_ticket',
        :priority    => MiqQueue::HIGH_PRIORITY,
        :role        => 'ems_operations',
        :zone        => my_zone,
        :args        => [userid, MiqServer.my_server.id, protocol]
      }

      MiqTask.generic_action_with_callback(task_opts, queue_opts)
    end
  end

  private

  def html5_console_enabled?
    !!::Settings.ems.ems_redhat&.consoles&.html5_enabled
  end
end
