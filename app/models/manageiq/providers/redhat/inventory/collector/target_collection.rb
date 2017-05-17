class ManageIQ::Providers::Redhat::Inventory::Collector::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Collector
  def initialize(_manager, _target)
    super
    parse_targets!
    infer_related_ems_refs!

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def clusters
    if target.kind_of? VmOrTemplate
      return collect_emsclusters
    end

    []
  end

  def networks
    if target.kind_of? Host
      return collect_networks
    end

    []
  end

  def storagedomains
    if target.kind_of? VmOrTemplate
      domains = if target.storages.empty?
                  collect_storagedomains
                else
                  collect_storagedomain(target.storages.map { |s| uuid_from_target(s) })
                end
      return domains
    end

    []
  end

  def collect_storagedomain(uuids)
    manager.with_provider_connection(VERSION_HASH) do |connection|
      uuids.collect do |uuid|
        connection.system_service.storage_domains_service.storage_domain_service(uuid).get
      end
    end
  end

  def datacenters
    if target.kind_of? VmOrTemplate
      return collect_datacenters
    end

    []
  end

  def hosts
    if target.kind_of? Host
      manager.with_provider_connection(VERSION_HASH) do |connection|
        return connection.system_service.hosts_service.host_service(uuid_from_target(target)).get
      end
    end

    []
  end

  def vms
    if target.kind_of? VmOrTemplate
      manager.with_provider_connection(VERSION_HASH) do |connection|
        return connection.system_service.vms_service.vm_service(uuid_from_target(target)).get
      end
    end

    []
  end

  def templates
    if target.kind_of? VmOrTemplate
      manager.with_provider_connection(VERSION_HASH) do |connection|
        connection.system_service.templates_service.list(:search => "vm.id=#{uuid_from_target(target)}")
      end
    end

    []
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
      # TODO
    end
  end

  def infer_related_vm_ems_refs_api!
    vms.each do |vm|
      # TODO
    end
  end

  def infer_related_host_ems_refs_db!
    changed_hosts = manager.hosts.where(:ems_ref => references(:hosts))

    changed_hosts.each do |host|
      # TODO
    end
  end

  def infer_related_host_ems_refs_api!
    hosts.each do |host|
      # TODO
    end
  end

  private

  def uuid_from_target(t)
    URI(t.ems_ref).path.split('/').last
  end

  def add_simple_target!(association, ems_ref)
    return if ems_ref.blank?

    target.add_target(:association => association, :manager_ref => {:ems_ref => ems_ref})
  end
end
