module ManageIQ::Providers::Redhat::Inventory::Persister::Shared::InfraGroup::DatacentersCollections
  extend ActiveSupport::Concern

  # group :datacenters
  def add_datacenters
    add_collection(infra, :datacenters) do |builder|
      arel = if targeted?
               manager.ems_folders.where(:type => 'Datacenter').where(:ems_ref => manager_refs) if manager_refs.present?
             else
               manager.ems_folders.where(:type => 'Datacenter')
             end

      builder.add_properties(:arel => arel) unless arel.nil?
    end
  end

  def add_ems_folders
    add_collection(infra, :ems_folders)
  end

  # group :datacenters
  def add_vm_folders
    add_collection(infra, :vm_folders, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.ems_folders

      builder.add_properties(:model_class => ::EmsFolder)

      arel = if targeted?
               manager.ems_folders.where(:uid_ems => manager_refs.collect { |ref| "#{URI(ref).path.split('/').last}_vm" }) if manager_refs.present?
             else
               manager.ems_folders.where(:name => 'vm')
             end

      builder.add_properties(:arel => arel) unless arel.nil?

      builder.add_inventory_attributes(%i(name type uid_ems hidden))
    end
  end

  # group :datacenters
  def add_host_folders
    add_collection(infra, :host_folders, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.ems_folders

      builder.add_properties(:model_class => ::EmsFolder)

      arel = if targeted?
               manager.ems_folders.where(:uid_ems => manager_refs.collect { |ref| "#{URI(ref).path.split('/').last}_host" }) if manager_refs.present?
             else
               manager.ems_folders.where(:name => 'host')
             end

      builder.add_properties(:arel => arel) unless arel.nil?

      builder.add_inventory_attributes(%i(name type uid_ems hidden))
    end
  end

  # group :datacenters
  def add_root_folders
    add_collection(infra, :root_folders, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.ems_folders

      builder.add_properties(:model_class => ::EmsFolder)

      arel = manager.ems_folders.where(:uid_ems => 'root_dc') if !targeted? || manager_refs.present?

      builder.add_properties(:arel => arel) unless arel.nil?

      builder.add_inventory_attributes(%i(name type uid_ems hidden))
    end
  end
end
