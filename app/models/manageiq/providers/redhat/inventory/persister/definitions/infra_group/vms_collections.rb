module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::VmsCollections
  extend ActiveSupport::Concern

  # group :vms
  def add_vms
    add_collection(infra, :vms) do |builder|
      if targeted?
        builder.add_properties(:arel => manager.vms.where(:ems_ref => manager_refs))
        # bug?
        builder.add_properties(:strategy => nil) if manager_refs.blank?
      end
    end
  end

  # group :vms
  def add_miq_templates
    add_collection(infra, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Redhat::InfraManager::Template)

      if targeted?
        builder.add_properties(:arel => manager.miq_templates.where(:ems_ref => manager_refs))
        # bug?
        builder.add_properties(:strategy => nil) if manager_refs.blank?
      end
    end
  end

  # group :vms
  def add_disks
    add_collection(infra, :disks) do |builder|
      if targeted?
        builder.add_properties(:arel => manager.disks.joins(:hardware => :vm_or_template).where(:hardware => {'vms' => {:ems_ref => manager_refs}}))
        # bug?
        builder.add_properties(:strategy => nil) if manager_refs.blank?
      end
    end
  end

  # group :vms
  def add_networks
    add_collection(infra, :networks) do |builder|
      builder.add_properties(:arel => manager.networks.joins(:hardware => :vm_or_template).where(:hardware => {'vms' => {:ems_ref => manager_refs}})) if targeted?
    end
  end

  # group :vms
  def add_hardwares
    add_collection(infra, :hardwares) do |builder|
      if targeted?
        builder.add_properties(:arel => manager.hardwares.joins(:vm_or_template).where('vms' => {:ems_ref => manager_refs}))
        # bug?
        builder.add_properties(:strategy => nil) if manager_refs.blank?
      end
    end
  end

  # group :vms
  def add_guest_devices
    add_collection(infra, :guest_devices) do |builder|
      builder.add_properties(:arel => GuestDevice.joins(:hardware => :vm_or_template).where(:hardware => {'vms' => {:ems_ref => manager_refs}})) if targeted?
    end
  end

  # group :vms
  def add_snapshots
    add_collection(infra, :snapshots) do |builder|
      builder.add_properties(:arel => Snapshot.joins(:vm_or_template).where('vms' => {:ems_ref => manager_refs})) if targeted?
    end
  end

  # group :vms
  def add_operating_systems
    add_collection(infra, :operating_systems) do |builder|
      if targeted?
        builder.add_properties(:arel => OperatingSystem.joins(:vm_or_template).where('vms' => {:ems_ref => manager_refs}))
        # bug?
        builder.add_properties(:strategy => nil) if manager_refs.blank?
      end
    end
  end

  # group :vms
  def add_vm_and_template_ems_custom_fields
    add_collection(infra, :vm_and_template_ems_custom_fields, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.add_properties(
        :model_class => ::CustomAttribute,
        :manager_ref => %i(name)
      )
      builder.add_inventory_attributes(%i(section name value source resource))
    end
  end
end
