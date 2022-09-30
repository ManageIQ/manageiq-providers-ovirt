class ManageIQ::Providers::Ovirt::InfraManager::Vm
  module RemoteConsole
    def console_supported?(type)
      type.upcase == 'NATIVE'
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
        :name       => 'console.vv'
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
end
