module ManageIQ::Providers::Redhat::Inventory::Persister::Shared::InfraGroup::VmsDependencyCollections
  extend ActiveSupport::Concern

  # group :vms_dependency
  def add_ems_folder_children
    add_collection(infra, :ems_folder_children, {},
                   {
                     :without_model_class       => true,
                     :auto_inventory_attributes => false
                   }) do |builder|

      builder.add_properties(:custom_save_block => ems_folder_children_custom_save_block)

      if !targeted? || references(:vms).present? # correct condition?
        builder.add_dependency_attributes(
          :clusters    => [collections[:ems_clusters]],
          :datacenters => [collections[:datacenters]],
          :vms         => [collections[:vms]],
          :templates   => [collections[:miq_templates]]
        )
      end
    end
  end

  # group :vms_dependency
  def add_ems_cluster_children
    add_collection(infra, :ems_cluster_children, {},
                   {
                     :without_model_class       => true,
                     :auto_inventory_attributes => false
                   }) do |builder|

      builder.add_properties(:custom_save_block => ems_cluster_children_save_block)

      if !targeted? || references(:vms).present? # correct condition?
        builder.add_dependency_attributes(
          :vms      => [collections[:vms]],
          :clusters => [collections[:ems_clusters]]
        )
      end
    end
  end

  # group :vms_dependency
  def add_snapshot_parent
    add_collection(infra, :snapshot_parent, {},
                   {
                     :auto_inventory_attributes => false,
                     :without_model_class       => true
                   }) do |builder|

      if !targeted? || references(:vms).present? # correct condition?
        builder.add_dependency_attributes(:snapshots => [collections[:snapshots]])
      end
    end
  end

  # ---

  # Custom save block for ems_folder_children IC
  def ems_folder_children_custom_save_block
    lambda do |ems, inventory_collection|
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
          host_folder.with_relationship_type("ems_metadata") { host_folder.add_child(cs) }

          vm_folder = EmsFolder.find_by(:uid_ems => "#{uid}_vm")
          vs = VmOrTemplate.find(vms.map(&:id))
          vm_folder.with_relationship_type("ems_metadata") { vm_folder.add_child(vs) }

          datacenter = EmsFolder.find(dc.id)
          datacenter.with_relationship_type("ems_metadata") { datacenter.add_child(host_folder) }
          datacenter.with_relationship_type("ems_metadata") { datacenter.add_child(vm_folder) }
          root_dc = EmsFolder.find_by(:uid_ems => 'root_dc', :ems_id => ems.id)
          root_dc.with_relationship_type("ems_metadata") { root_dc.add_child(datacenter) }
          ems.with_relationship_type("ems_metadata") { ems.add_child(root_dc) }
        end
      end
    end
  end

  # Custom save block for ems_cluster_children IC
  def ems_cluster_children_save_block
    lambda do |_ems, inventory_collection|
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
  end
end
