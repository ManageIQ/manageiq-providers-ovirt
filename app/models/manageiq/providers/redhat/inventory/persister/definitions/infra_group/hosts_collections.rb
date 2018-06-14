module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::HostsCollections
  extend ActiveSupport::Concern

  # group :hosts
  def add_hosts
    add_collection(infra, :hosts) do |builder|
      builder.add_properties(
        :manager_ref            => %i(uid_ems),
        :custom_reconnect_block => hosts_custom_reconnect_block
      )

      if targeted?
        builder.add_properties(:arel => manager.hosts.where(:ems_ref => manager_refs)) if manager_refs.present?
      end

      builder.add_builder_params(:ems_id => ->(persister) { persister.manager.id })
    end
  end

  # group :hosts
  def add_host_hardwares
    add_collection(infra, :host_hardwares) do |builder|
      if targeted? && manager_refs.present?
        builder.add_properties(:arel => manager.host_hardwares.joins(:host).where('hosts' => {:ems_ref => manager_refs}))
      end
    end
  end

  # group :hosts
  def add_host_networks
    add_collection(infra, :host_networks) do |builder|
      if targeted? && manager_refs.present?
        builder.add_properties(:arel => manager.networks.joins(:hardware => :host).where(:hardware => {'hosts' => {:ems_ref => manager_refs}}))
      end
    end
  end

  # group :hosts
  def add_host_operating_systems
    add_collection(infra, :host_operating_systems) do |builder|
      if targeted? && manager_refs.present?
        builder.add_properties(:arel => ::OperatingSystem.joins(:host).where('hosts' => {:ems_ref => manager_refs}))
      end
    end
  end

  # group :hosts
  def add_host_storages
    add_collection(infra, :host_storages) do |builder|
      if targeted? && manager_refs.present?
        builder.add_properties(:arel => manager.host_storages.where(:ems_ref => manager_refs))
      end
    end
  end

  # group :hosts
  def add_host_switches
    add_collection(infra, :host_switches) do |builder|
      if targeted? && manager_refs.present?
        builder.add_properties(:arel => HostSwitch.joins(:host).where('hosts' => {:ems_ref => manager_refs}))
      end
    end
  end

  # ---

  # Custom reconnect block for Hosts IC
  def hosts_custom_reconnect_block
    lambda do |inventory_collection, inventory_objects_index, attributes_index|
      relation = inventory_collection.model_class.where(:ems_id => nil)

      return if relation.count <= 0

      inventory_objects_index.each_slice(100) do |batch|
        relation.where(inventory_collection.manager_ref.first => batch.map(&:first)).each do |record|
          index = inventory_collection.object_index_with_keys(inventory_collection.manager_ref_to_cols, record)

          # We need to delete the record from the inventory_objects_index and attributes_index, otherwise it
          # would be sent for create.
          inventory_object = inventory_objects_index.delete(index)
          hash             = attributes_index.delete(index)

          record.assign_attributes(hash.except(:id, :type))
          if !inventory_collection.check_changed? || record.changed?
            record.save!
            inventory_collection.store_updated_records(record)
          end

          inventory_object.id = record.id
        end
      end
    end
  end
end
