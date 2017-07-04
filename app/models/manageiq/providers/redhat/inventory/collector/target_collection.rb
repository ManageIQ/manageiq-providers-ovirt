class ManageIQ::Providers::Redhat::Inventory::Collector::TargetCollection < ManageIQ::Providers::Redhat::Inventory::Collector
  def initialize(_manager, _target)
    super
    parse_targets!
    infer_related_ems_refs!

    # Reset the target cache, so we can access new targets inside
    target.manager_refs_by_association_reset
  end

  def clusters
    # TODO
  end

  def vmpools
    # TODO
  end

  def networks
    # TODO
  end

  def storagedomains
    # TODO
  end

  def datacenters
    # TODO
  end

  def hosts
    # TODO
  end

  def vms
    # TODO
  end

  def templates
    # TODO
  end

  def references(collection)
    target.manager_refs_by_association.try(:[], collection).try(:[], :ems_ref).try(:to_a) || []
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

  def add_simple_target!(association, ems_ref)
    return if ems_ref.blank?

    target.add_target(:association => association, :manager_ref => {:ems_ref => ems_ref})
  end

  def infer_related_ems_refs!
    # TODO: check whether we can do it for either vms or hosts
    unless references(:vms).blank? || references(:hosts).blank?
      infer_related_vm_ems_refs_db!
      infer_related_vm_ems_refs_api!
    end
  end

  def infer_related_vm_ems_refs_db!
    # TODO
  end

  def infer_related_vm_ems_refs_api!
    # TODO
  end
end
