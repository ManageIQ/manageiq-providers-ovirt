module ManageIQ::Providers::Redhat::InfraManager::Vm::Operations::Relocation
  extend ActiveSupport::Concern

  def raw_migrate(host, pool = nil, priority = "defaultPriority", state = nil)
    raise _("Host not specified, unable to migrate VM") unless host.kind_of?(Host)

    if pool.nil?
      pool = host.default_resource_pool || (host.ems_cluster && host.ems_cluster.default_resource_pool)
      unless pool.kind_of?(ResourcePool)
        raise _("Default Resource Pool for Host <%{name}> not found, unable to migrate VM") % {:name => host.name}
      end
    else
      unless pool.kind_of?(ResourcePool)
        raise _("Specified Resource Pool <%{pool_name}> for Host <%{name}> is invalid, unable to migrate VM") %
                {:pool_name => pool.inspect, :name => host.name}
      end
    end

    if host_id == host.id
      raise _("The VM '%{name}' can not be migrated to the same host it is already running on.") % {:name => name}
    end

    host_mor = host.ems_ref_obj
    pool_mor = pool.ems_ref_obj
    run_command_via_parent(:vm_migrate, :host => host_mor, :pool => pool_mor, :priority => priority, :state => state)
  end
end
