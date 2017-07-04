class ManageIQ::Providers::Redhat::InventoryCollectionDefault::InfraManager < ManagerRefresh::InventoryCollectionDefault::CloudManager
  # TODO: above ManagerRefresh::InventoryCollectionDefault::CloudManager is wrong we need InfraManager here
  class << self
    # TODO: check correctness
    def vms(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Redhat::InfraManager::Vm,
      }
      super(attributes.merge!(extra_attributes))
    end

    # TODO: check correctness
    def miq_templates(extra_attributes = {})
      attributes = {
        :model_class                 => ::ManageIQ::Providers::Redhat::InfraManager::Template,
        :inventory_object_attributes => [
          :type,
          :ext_management_system,
          :uid_ems,
          :ems_ref,
          :name,
          :location,
          :vendor,
          :raw_power_state,
          :template,
          :publicly_available,
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    # TODO: check correctness
    def hardwares(extra_attributes = {})
      attributes = {
        :inventory_object_attributes => [
          :guest_os,
          :bitness,
          :virtualization_type,
          :root_device_type,
          :vm_or_template,
        ]
      }

      super(attributes.merge!(extra_attributes))
    end

    # TODO: check correctness
    def disks(extra_attributes = {})
      attributes = {
        :inventory_object_attributes => %i(hardware device_name location size backing),
      }

      super(attributes.merge!(extra_attributes))
    end
  end
end
