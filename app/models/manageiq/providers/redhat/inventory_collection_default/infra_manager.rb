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

    def vm_folders(extra_attributes = {})
      attributes = {
        :model_class                 => ::EmsFolder,
        :inventory_object_attributes => [
          :name,
          :type,
          :uid_ems,
          :hidden
        ],
        :association                 => :vm_folders,
        :manager_ref                 => [:uid_ems],
        :attributes_blacklist        => [:ems_children],
        :builder_params              => {
          :ems_id => ->(persister) { persister.manager.id },
        },
      }

      attributes.merge!(extra_attributes)
    end

    def host_folders(extra_attributes = {})
      attributes = {
        :model_class                 => ::EmsFolder,
        :inventory_object_attributes => [
          :name,
          :type,
          :uid_ems,
          :hidden
        ],
        :association                 => :host_folders,
        :manager_ref                 => [:uid_ems],
        :attributes_blacklist        => [:ems_children],
        :builder_params              => {
          :ems_id => ->(persister) { persister.manager.id },
        },
      }

      attributes.merge!(extra_attributes)
    end

    def root_folders(extra_attributes = {})
      attributes = {
        :model_class                 => ::EmsFolder,
        :inventory_object_attributes => [
          :name,
          :type,
          :uid_ems,
          :hidden
        ],
        :association                 => :root_folders,
        :manager_ref                 => [:uid_ems],
        :attributes_blacklist        => [:ems_children],
        :builder_params              => {
          :ems_id => ->(persister) { persister.manager.id },
        },
      }

      attributes.merge!(extra_attributes)
    end

    def ems_folder_children(extra_attributes = {})
      folder_children_save_block = lambda do |ems, inventory_collection|
        cluster_collection = inventory_collection.dependency_attributes[:clusters].try(:first)
        vm_collection = inventory_collection.dependency_attributes[:vms].try(:first)
        template_collection = inventory_collection.dependency_attributes[:templates].try(:first)
        datacenter_collection = inventory_collection.dependency_attributes[:datacenters].try(:first)

        datacenter_collection.data.each do |dc|
          uid = dc.uid_ems

          clusters = cluster_collection.data.select { |cluster| cluster.datacenter_id == uid }
          cluster_refs = clusters.map(&:ems_ref)

          vms = vm_collection.data.select { |vm| cluster_refs.include? vm.ems_cluster.ems_ref }
          templates = template_collection.data.select { |t| cluster_refs.include? t.ems_cluster.ems_ref }

          ActiveRecord::Base.transaction do
            host_folder = EmsFolder.find_by(:uid_ems => "#{uid}_host")
            cs = EmsCluster.find(clusters.map(&:id))
            cs.each do |c|
              host_folder.with_relationship_type("ems_metadata") { host_folder.add_child c }
            end

            vm_folder = EmsFolder.find_by(:uid_ems => "#{uid}_vm")
            vs = VmOrTemplate.find(vms.map(&:id))
            vs.each do |v|
              vm_folder.with_relationship_type("ems_metadata") { vm_folder.add_child v }
            end

            ts = MiqTemplate.find(templates.map(&:id))
            ts.each do |t|
              vm_folder.with_relationship_type("ems_metadata") { vm_folder.add_child t }
            end

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
        vm_collection = inventory_collection.dependency_attributes[:vms].try(:first)

        cluster_collection.each do |cluster|
          vms = vm_collection.data.select { |vm| cluster.ems_ref == vm.ems_cluster.ems_ref }

          ActiveRecord::Base.transaction do
            vs = VmOrTemplate.find(vms.map(&:id))
            rp = ResourcePool.find_by(:uid_ems => "#{cluster.uid_ems}_respool")
            vs.each do |v|
              rp.with_relationship_type("ems_metadata") { rp.add_child v }
            end
            c = EmsCluster.find(cluster.id)
            c.with_relationship_type("ems_metadata") { c.add_child rp }
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
