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
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.hosts.where(:ems_ref => references(:hosts)) # TODO why are we using ems_ref instead of uid_ems?
          end
        )
      end

      builder.add_builder_params(:ems_id => ->(persister) { persister.manager.id })
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
