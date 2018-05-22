class ManageIQ::Providers::Redhat::Inventory::Collector::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Collector
  # TODO: review the changes here and find common parts with ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4
  include Vmdb::Logging

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
      references(:ems_clusters).each do |ems_ref|
        begin
          clusters << connection.system_service.clusters_service.cluster_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end

    clusters
  end

  def networks
    nets = []
    return nets if references(:networks).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:networks).each do |ems_ref|
        begin
          nets << connection.system_service.networks_service.network_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end

    nets
  end

  def storagedomains
    domains = []
    return domains if references(:storagedomains).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:storagedomains).each do |ems_ref|
        begin
          domains << connection.system_service.storage_domains_service.storage_domain_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end

    domains
  end

  def datacenters
    dcs = []
    return dcs if references(:datacenters).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:datacenters).each do |ems_ref|
        begin
          dcs << connection.system_service.data_centers_service.data_center_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end

    dcs
  end

  def hosts
    h = []
    return h if references(:hosts).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      references(:hosts).each do |ems_ref|
        begin
          h << connection.system_service.hosts_service.host_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end

    h
  end

  def vms
    @vms = manager.with_provider_connection(VERSION_HASH) do |connection|
      select_vms(references(:vms)).map do |ems_ref|
        begin
          connection.system_service.vms_service.vm_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end if @vms.blank?
    @vms
  end

  def select_vms(references_lst)
    references_lst.select { |ref| ref.include?('vms') }
  end

  def select_templates(references_lst)
    references_lst.select { |ref| ref.include?('templates') }
  end

  def templates
    t = []
    return t if select_templates(references(:vms)).blank?

    manager.with_provider_connection(VERSION_HASH) do |connection|
      select_templates(references(:vms)).each do |ems_ref|
        begin
          # returns OvirtSDK4::List
          t << connection.system_service.templates_service.template_service(uuid_from_ems_ref(ems_ref)).get
        rescue OvirtSDK4::Error # when 404
          nil
        end
      end
    end

    t
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
    changed_vms = manager.vms_and_templates.where(:ems_ref => references(:vms))

    changed_vms.each do |vm|
      unless vm.ems_cluster.nil?
        # when we target new vm
        add_simple_target!(:ems_clusters, vm.ems_cluster.ems_ref)
        add_simple_target!(:datacenters, vm.parent_datacenter.ems_ref)
      end

      vm.storages.collect(&:ems_ref).compact.each { |ems_ref| add_simple_target!(:storagedomains, ems_ref) } unless vm.storages.nil?
      add_simple_target!(:templates, vm.ems_ref)
    end
  end

  def infer_related_vm_ems_refs_api!
    vms_and_templates = Array(vms) + Array(templates)
    vms_and_templates.each do |vm|
      clusters = collect_ems_clusters
      clusters.each do |c|
        add_simple_target!(:ems_clusters, ems_ref_from_sdk(c))
        if c.id == vm.cluster&.id
          add_simple_target!(:datacenters, ems_ref_from_sdk(c.data_center))
        end
      end

      disks = collect_attached_disks(vm)
      disks.each do |disk|
        disk.storage_domains.to_miq_a.each do |sd|
          add_simple_target!(:storagedomains, ems_ref_from_sdk(sd))
        end
      end
      add_simple_target!(:templates, ems_ref_from_sdk(vm))
    end
  end

  def infer_related_host_ems_refs_db!
    changed_hosts = manager.hosts.where(:ems_ref => references(:hosts))

    changed_hosts.each do |host|
      add_simple_target!(:ems_clusters, uuid_from_target(host.ems_cluster))
      host.storages.each do |storage|
        add_simple_target!(:storagedomains, uuid_from_target(storage))
      end
      host.switches.each do |switch|
        add_simple_target!(:networks, switch.uid_ems)
      end
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

  def ems_ref_from_sdk(object)
    ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(object.href)
  end

  def add_simple_target!(association, ems_ref)
    return if ems_ref.blank?

    target.add_target(:association => association, :manager_ref => {:ems_ref => ems_ref})
  end
end
