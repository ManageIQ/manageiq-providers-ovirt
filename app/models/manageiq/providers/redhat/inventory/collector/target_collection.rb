class ManageIQ::Providers::Redhat::Inventory::Collector::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Collector
  def initialize(_manager, _target)
    super
    parse_targets!
    infer_related_ems_refs!

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def ems_clusters
    clusters = []
    return clusters if references(:ems_clusters).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:ems_clusters).each do |id|
        clusters + connection.system_service.clusters_service.cluster_service(id).get
      end
    end

    clusters
  end

  def networks
    nets = []
    return domains if references(:networks).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:networks).each do |id|
        nets + connection.system_service.networks_service.network_service(id).get
      end
    end

    nets
  end

  def storagedomains
    domains = []
    return domains if references(:storagedomains).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:storagedomains).each do |id|
        domains + connection.system_service.storage_domains_service.storage_domain_service(id).get
      end
    end

    domains
  end

  def datacenters
    dcs = []
    return dcs if references(:datacenters).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:datacenters).each do |id|
        dcs + connection.system_service.data_centers_service.data_center_service(id).get
      end
    end

    dcs
  end

  def hosts
    h = []
    return h if references(:hosts).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:vms).each do |ems_ref|
        h + connection.system_service.hosts_service.host_service(uuid_from_ems_ref(ems_ref)).get
      end
    end

    h
  end

  def vms
    v = []
    return v if references(:vms).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:vms).each do |ems_ref|
        v + connection.system_service.vms_service.vm_service(uuid_from_ems_ref(ems_ref)).get
      end
    end

    v
  end

  def templates
    temp = []
    return temp if references(:templates).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:templates).each do |id|
        temp + connection.system_service.templates_service.list(:search => "vm.id=#{id}")
      end
    end

    temp
  end

  def references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :ems_ref).try(:to_a) || []
  end

  def name_references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :name).try(:to_a) || []
  end

  def parse_targets!
    target.targets.each do |t|
      case t
      when VmOrTemplate
        parse_vm_target!(t)
      when Host
        parse_host_target!(t)
      end
    end
  end

  def parse_vm_target!(t)
    add_simple_target!(:vms, t.ems_ref)
  end

  def parse_host_target!(t)
    add_simple_target!(:hosts, t.ems_ref)
  end

  def infer_related_ems_refs!
    unless references(:vms).blank?
      infer_related_vm_ems_refs_db!
      infer_related_vm_ems_refs_api!
    end

    unless references(:hosts).blank?
      infer_related_host_ems_refs_db!
      infer_related_host_ems_refs_api!
    end
  end

  def infer_related_vm_ems_refs_db!
    changed_vms = manager.vms.where(:ems_ref => references(:vms))

    changed_vms.each do |vm|
      add_simple_target!(:ems_clusters, uuid_from_target(vm.ems_cluster))
      vm.storages.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:storagedomains, uuid_from_ems_ref(ems_ref)) }
      add_simple_target!(:datacenters, uuid_from_target(vm.parent_datacenter))
      add_simple_target!(:templates, uuid_from_target(vm))
    end
  end

  def infer_related_vm_ems_refs_api!
    vms.each do |vm|
      add_simple_target!(:ems_clusters, vm.cluster.id)
      disks = collect_attached_disks(vm)
      disks.each do |disk|
        disk.storage_domains.to_miq_a.each do |sd|
          add_simple_target!(:storagedomains, sd.id)
        end
      end
      add_simple_target!(:datacenters, vm.cluster.data_center.id)
      add_simple_target!(:templates, vm.id)
    end
  end

  def infer_related_host_ems_refs_db!
    changed_hosts = manager.hosts.where(:ems_ref => references(:hosts))

    changed_hosts.each do |host|
      add_simple_target!(:ems_clusters, uuid_from_target(host.ems_cluster))
      # TODO: host.hardware.networks do not have ems_ref nor ems_uid
    end
  end

  def infer_related_host_ems_refs_api!
    hosts.each do |host|
      add_simple_target!(:ems_clusters, host.cluster.id)
      host.network_attachments.each do |attachement|
        add_simple_target!(:networks, attachement.network.id)
      end
    end
  end

  private

  def uuid_from_target(t)
    uuid_from_ems_ref(t.ems_ref)
  end

  def uuid_from_ems_ref(ems_ref)
    URI(ems_ref).path.split('/').last
  end

  def add_simple_target!(association, ems_ref)
    return if ems_ref.blank?

    target.add_target(:association => association, :manager_ref => {:ems_ref => ems_ref})
  end
end
