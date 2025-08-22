class ManageIQ::Providers::Ovirt::InfraManager::Vm
  module RemoteConsole
    extend ActiveSupport::Concern

    included do
      supports :native_console
      # NOTE: this says that these are supported IF html_console is enabled
      supports(:html5_console) { _("Html5 console is disabled by default, check settings to enable it") unless html5_console_enabled? }
      supports(:console)       { unsupported_reason(:html5_console) }
      supports(:spice_console) { unsupported_reason(:html5_console) }
      supports(:vnc_console)   { unsupported_reason(:html5_console) }
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

    def validate_native_console_support
      raise(MiqException::RemoteConsoleNotSupportedError,
            "Remote viewer requires the vm to be registered with a management system.") if ext_management_system.nil?

      raise(MiqException::RemoteConsoleNotSupportedError,
            "Remote viewer requires the vm to be running.") if state != "on"
    end

    def native_console_connection
      validate_native_console_support

      conn = ext_management_system.ovirt_services.native_console_connection(self)
      raise(MiqException::RemoteConsoleNotSupportedError, 'No remote native console available for this vm') unless conn

      {
        :connection => conn,
        :type       => 'application/x-virt-viewer',
        :name       => 'console.vv',
        :proto      => 'native'
      }
    end

    def native_console_connection_queue(userid)
      task_opts = {
        :action => "getting Vm #{name} native console connection settings for user #{userid}",
      }

      queue_opts = {
        :class_name  => self.class.name,
        :instance_id => id,
        :method_name => 'native_console_connection',
        :priority    => MiqQueue::HIGH_PRIORITY,
        :role        => 'ems_operations',
        :zone        => my_zone,
        :args        => []
      }

      MiqTask.generic_action_with_callback(task_opts, queue_opts)
    end
  end

  private

  def html5_console_enabled?
    !!::Settings.ems.ems_ovirt&.consoles&.html5_enabled
  end
end
