class ManageIQ::Providers::Redhat::Inventory::Persister::InfraManager < ManageIQ::Providers::Redhat::Inventory::Persister
  def initialize_inventory_collections
    add_collection(infra, :disks)
    add_collection(infra, :ems_clusters, :secondary_refs => {:by_uid_ems => %i[uid_ems]})
    add_collection(infra, :ems_folders)
    add_collection(infra, :guest_devices)
    add_collection(infra, :hardwares)
    add_collection(infra, :vm_and_template_ems_custom_fields)
    add_collection(infra, :hosts)
    add_collection(infra, :host_guest_devices)
    add_collection(infra, :host_hardwares)
    add_collection(infra, :host_networks)
    add_collection(infra, :host_operating_systems)
    add_collection(infra, :host_storages)
    add_collection(infra, :host_switches)
    add_collection(infra, :host_virtual_switches)
    add_collection(infra, :lans)
    add_collection(infra, :networks)
    add_collection(infra, :operating_systems)
    add_collection(infra, :vms)

    add_datacenters
    add_miq_templates
    add_resource_pools
    add_snapshots
    add_storages

    add_collection(infra, :parent_blue_folders)
    add_collection(infra, :root_folder_relationship)
    add_collection(infra, :vm_resource_pools)
    add_collection(infra, :vm_parent_blue_folders)
  end

  # group :ems_clusters
  def add_resource_pools
    add_collection(infra, :resource_pools) do |builder|
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.resource_pools.where(:uid_ems => references(:ems_clusters).collect { |ref| "#{URI(ref).path.split('/').last}_respool" })
          end
        )
      end
    end
  end

  def add_datacenters
    add_collection(infra, :datacenters) do |builder|
      builder.add_properties(:arel => manager.ems_folders.where(:type => 'Datacenter'))

      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            manager.ems_folders.where(:type => 'Datacenter').where(:ems_ref => references(:datacenters))
          end
        )
      end
    end
  end

  def add_storages
    add_collection(infra, :storages) do |builder|
      if targeted?
        builder.add_targeted_arel(
          lambda do |_inventory_collection|
            ::Storage.where(:ems_ref => references(:storagedomains))
          end
        )
      end
    end
  end

  def add_miq_templates
    add_collection(infra, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Redhat::InfraManager::Template)

      builder.add_properties(:manager_uuids => references(:vms)) if targeted?
    end
  end

  def add_snapshots
    add_collection(infra, :snapshots) do |builder|
      builder.add_properties(
        :manager_ref => %i(uid),
        :strategy    => :local_db_find_missing_references,
      )
    end
  end

  def add_ems_folder_children
    add_collection(infra, :ems_folder_children, {},
                   {
                     :without_model_class       => true,
                     :auto_inventory_attributes => false
                   }) do |builder|

      builder.add_properties(:custom_save_block => ems_folder_children_custom_save_block)

      builder.add_dependency_attributes(
        :clusters    => [collections[:ems_clusters]],
        :datacenters => [collections[:datacenters]],
        :vms         => [collections[:vms]],
        :templates   => [collections[:miq_templates]]
      )
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

      builder.add_dependency_attributes(
        :vms      => [collections[:vms]],
        :clusters => [collections[:ems_clusters]]
      )
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

      vms_and_templates         = (vm_collection.data + template_collection.data).reject { |vm| vm.ems_cluster.nil? }
      indexed_vms_and_templates = vms_and_templates.each_with_object({}) { |vm, obj| (obj[vm.ems_cluster.ems_ref] ||= []) << vm }

      datacenter_collection.data.each do |dc|
        uid = dc.uid_ems

        clusters = cluster_collection.data.select { |cluster| cluster.datacenter_id == uid }
        cluster_refs = clusters.map(&:ems_ref)

        vms = cluster_refs.map { |x| indexed_vms_and_templates[x] }.flatten.compact

        ActiveRecord::Base.transaction do
          host_folder = ems.ems_folders.find_by(:uid_ems => "#{uid}_host")
          cs = EmsCluster.find(clusters.map(&:id))
          host_folder.with_relationship_type("ems_metadata") { host_folder.add_child(cs) }

          vm_folder = ems.ems_folders.find_by(:uid_ems => "#{uid}_vm")
          vs = VmOrTemplate.find(vms.map(&:id))
          vm_folder.with_relationship_type("ems_metadata") { vm_folder.add_child(vs) }

          datacenter = EmsFolder.find(dc.id)
          datacenter.with_relationship_type("ems_metadata") { datacenter.add_child(host_folder) }
          datacenter.with_relationship_type("ems_metadata") { datacenter.add_child(vm_folder) }
          root_dc = ems.ems_folders.find_by(:uid_ems => 'root_dc')
          root_dc.with_relationship_type("ems_metadata") { root_dc.add_child(datacenter) }
          ems.with_relationship_type("ems_metadata") { ems.add_child(root_dc) }
        end
      end
    end
  end

  # Custom save block for ems_cluster_children IC
  def ems_cluster_children_save_block
    lambda do |ems, inventory_collection|
      cluster_collection = inventory_collection.dependency_attributes[:clusters].try(:first)
      cluster_model      = cluster_collection.model_class

      vm_collection = inventory_collection.dependency_attributes[:vms].try(:first)
      vm_model      = vm_collection.model_class

      vms_by_cluster = Hash.new { |h, k| h[k] = [] }
      vm_collection.data.each { |vm| vms_by_cluster[vm.ems_cluster&.id] << vm }

      ActiveRecord::Base.transaction do
        clusters_by_id = cluster_model.find(cluster_collection.data.map(&:id)).index_by(&:id)
        vms_by_id      = vm_model.find(vm_collection.data.map(&:id)).index_by(&:id)

        clusters_by_id.each do |cluster_id, cluster|
          rp = ems.resource_pools.find_by(:uid_ems => "#{cluster.uid_ems}_respool")
          cluster.with_relationship_type("ems_metadata") { cluster.add_child(rp) }

          vms = vms_by_id.values_at(*vms_by_cluster[cluster_id]&.map(&:id) || [])
          rp.with_relationship_type("ems_metadata") { rp.add_children(vms) }
        end
      end
    end
  end
end
