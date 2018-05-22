class ManageIQ::Providers::Redhat::InventoryCollectionDefault::InfraManager < ManagerRefresh::InventoryCollectionDefault::InfraManager
  class << self
    def vms(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Redhat::InfraManager::Vm,
      }

      super(attributes.merge!(extra_attributes))
    end

    def miq_templates(extra_attributes = {})
      attributes = {
        :model_class => ::ManageIQ::Providers::Redhat::InfraManager::Template,
      }

      super(attributes.merge!(extra_attributes))
    end

    def hosts(extra_attributes = {})
      attributes = {
        :model_class                 => ::Host,
        :association                 => :hosts,
        :manager_ref                 => [:uid_ems],
        :inventory_object_attributes => %i(
          type
          ems_ref
          ems_ref_obj
          name
          hostname
          ipaddress
          uid_ems
          vmm_vendor
          vmm_product
          vmm_version
          vmm_buildnumber
          connection_state
          power_state
          ems_cluster
          ipmi_address
          maintenance
        ),
        :builder_params              => {
          :ems_id => ->(persister) { persister.manager.id },
        },
        :custom_reconnect_block      => lambda do |inventory_collection, inventory_objects_index, attributes_index|
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
      }

      attributes.merge!(extra_attributes)
    end

    def vm_and_template_ems_custom_fields(extra_attributes = {})
      attributes = {
        :model_class                 => ::CustomAttribute,
        :manager_ref                 => [:name],
        :association                 => :vm_and_template_ems_custom_fields,
        :inventory_object_attributes => %i(
          section
          name
          value
          source
          resource
        ),
      }

      attributes.merge!(extra_attributes)
    end

    def ems_folder_children(extra_attributes = {})
      folder_children_save_block = lambda do |ems, inventory_collection|
        cluster_collection = inventory_collection.dependency_attributes[:clusters].try(:first)
        vm_collection = inventory_collection.dependency_attributes[:vms].try(:first)
        template_collection = inventory_collection.dependency_attributes[:templates].try(:first)
        datacenter_collection = inventory_collection.dependency_attributes[:datacenters].try(:first)

        vms_and_templates = vm_collection.data + template_collection.data
        indexed_vms_and_templates = vms_and_templates.each_with_object({}) { |vm, obj| (obj[vm.ems_cluster.ems_ref] ||= []) << vm }

        datacenter_collection.data.each do |dc|
          uid = dc.uid_ems

          clusters = cluster_collection.data.select { |cluster| cluster.datacenter_id == uid }
          cluster_refs = clusters.map(&:ems_ref)

          vms = cluster_refs.map { |x| indexed_vms_and_templates[x] }.flatten.compact

          ActiveRecord::Base.transaction do
            host_folder = EmsFolder.find_by(:uid_ems => "#{uid}_host")
            cs = EmsCluster.find(clusters.map(&:id))
            host_folder.with_relationship_type("ems_metadata") { host_folder.add_child cs }

            vm_folder = EmsFolder.find_by(:uid_ems => "#{uid}_vm")
            vs = VmOrTemplate.find(vms.map(&:id))
            vm_folder.with_relationship_type("ems_metadata") { vm_folder.add_child vs }

            datacenter = EmsFolder.find(dc.id)
            datacenter.with_relationship_type("ems_metadata") { datacenter.add_child host_folder }
            datacenter.with_relationship_type("ems_metadata") { datacenter.add_child vm_folder }
            root_dc = EmsFolder.find_by(:uid_ems => 'root_dc', :ems_id => ems.id)
            root_dc.with_relationship_type("ems_metadata") { root_dc.add_child datacenter }
            ems.with_relationship_type("ems_metadata") { ems.add_child root_dc }
          end
        end
      end

      attributes = {
        :association       => :ems_folder_children,
        :custom_save_block => folder_children_save_block,
      }

      attributes.merge!(extra_attributes)
    end

    def ems_clusters_children(extra_attributes = {})
      ems_cluster_children_save_block = lambda do |_ems, inventory_collection|
        cluster_collection = inventory_collection.dependency_attributes[:clusters].try(:first)
        cluster_model      = cluster_collection.model_class

        vm_collection = inventory_collection.dependency_attributes[:vms].try(:first)
        vm_model      = vm_collection.model_class

        vms_by_cluster = Hash.new { |h, k| h[k] = []}
        vm_collection.data.each { |vm| vms_by_cluster[vm.ems_cluster&.id] << vm }

        ActiveRecord::Base.transaction do
          clusters_by_id = cluster_model.find(cluster_collection.data.map(&:id)).index_by(&:id)
          vms_by_id      = vm_model.find(vm_collection.data.map(&:id)).index_by(&:id)

          clusters_by_id.each do |cluster_id, cluster|
            rp = ResourcePool.find_by(:uid_ems => "#{cluster.uid_ems}_respool")
            cluster.with_relationship_type("ems_metadata") { cluster.add_child(rp) }

            vms = vms_by_id.values_at(*vms_by_cluster[cluster_id]&.map(&:id) || [])
            rp.with_relationship_type("ems_metadata") { rp.add_children(vms) }
          end
        end
      end

      attributes = {
        :association       => :ems_cluster_children,
        :custom_save_block => ems_cluster_children_save_block,
      }

      attributes.merge!(extra_attributes)
    end
  end
end
