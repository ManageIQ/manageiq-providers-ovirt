class ManageIQ::Providers::Redhat::InventoryCollectionDefault::InfraManager < ManagerRefresh::InventoryCollectionDefault::InfraManager
  class << self
    def vms(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::InfraManager::Vm,
        :inventory_object_attributes => [
          :type,
          :ems_ref,
          :ems_ref_obj,
          :uid_ems,
          :connection_state,
          :vendor,
          :name,
          :location,
          :template,
          :memory_reserve,
          :raw_power_state,
          :boot_time,
          :host,
          :ems_cluster,
          :storages,
          :storage,
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    def disks(extra_attributes = {})
      attributes = {
        :model_class                 => ::Disk,
        :inventory_object_attributes => [
          :device_name,
          :device_type,
          :controller_type,
          :present,
          :filename,
          :location,
          :size,
          :size_on_disk,
          :disk_type,
          :mode,
          :bootable,
          :storage
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    def nics(extra_attributes = {})
      attributes = {
        :model_class                 => ::Network,
        :inventory_object_attributes => [
          :ipaddress,
          :hostname
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    def hardwares(extra_attributes = {})
      attributes = {
        :model_class                 => ::Hardware,
        :inventory_object_attributes => [
          :guest_os,
          :annotation,
          :cpu_cores_per_socket,
          :cpu_sockets,
          :cpu_total_cores,
          :memory_mb
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    def datacenters(extra_attributes = {})
      attributes = {
        :model_class                 => ::Datacenter,
        :inventory_object_attributes => [
          :name,
          :type,
          :ems_ref,
          :ems_ref_obj,
          :uid_ems,
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    def resource_pools(extra_attributes = {})
      attributes = {
        :model_class                 => ::ResourcePool,
        :inventory_object_attributes => [
          :name,
          :uid_ems,
          :is_default,
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    def ems_clusters(extra_attributes = {})
      attributes = {
        :model_class                 => ::EmsCluster,
        :inventory_object_attributes => [
          :ems_ref,
          :ems_ref_obj,
          :uid_ems,
          :name,
          :datacenter_id,
        ]
      }

      super(attributes.merge!(extra_attributes))
    end
  end
end
