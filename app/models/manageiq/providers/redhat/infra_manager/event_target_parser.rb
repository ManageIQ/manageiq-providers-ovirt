class ManageIQ::Providers::Redhat::InfraManager::EventTargetParser
  attr_reader :ems_event

  # @param ems_event [EmsEvent] EmsEvent object
  def initialize(ems_event)
    @ems_event = ems_event
  end

  # Parses all targets that are present in the EmsEvent given in the initializer
  #
  # @return [Array] Array of InventoryRefresh::Target objects
  def parse
    target_collection = InventoryRefresh::TargetCollection.new(:manager => ems_event.ext_management_system, :event => ems_event)

    data = ems_event.full_data

    add_vm_target(target_collection, data["vm"])             if data["vm"].present?
    add_template_target(target_collection, data["template"]) if data["template"].present?
    add_cluster_target(target_collection, data["cluster"])   if data["cluster"].present?

    target_collection.targets
  end

  private

  def add_vm_target(target_collection, vm_data)
    ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(vm_data["href"])
    target_collection.add_target(:association => :vms, :manager_ref => {:ems_ref => ems_ref})
  end

  def add_template_target(target_collection, template_data)
    ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(template_data["href"])
    target_collection.add_target(:association => :miq_templates, :manager_ref => {:ems_ref => ems_ref})
  end

  def add_cluster_target(target_collection, cluster_data)
    ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(cluster_data["href"])
    target_collection.add_target(:association => :ems_clusters, :manager_ref => {:ems_ref => ems_ref})
  end
end
