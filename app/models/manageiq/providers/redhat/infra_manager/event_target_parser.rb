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
    parse_ems_event_targets(ems_event)
  end

  private

  # Parses list of InventoryRefresh::Target out of the given EmsEvent
  #
  # @param event [EmsEvent] EmsEvent object
  # @return [Array] Array of InventoryRefresh::Target objects
  def parse_ems_event_targets(event)
    target_collection = InventoryRefresh::TargetCollection.new(:manager => event.ext_management_system, :event => event)

    if ems_event.event_type.start_with?("orchestration.stack")
      collect_orchestration_stack_references!(target_collection, ems_event)
    elsif ems_event.event_type.start_with?("image.")
      collect_image_references!(target_collection, ems_event)
    elsif ems_event.event_type.start_with?("aggregate.")
      collect_host_aggregate_references!(target_collection, ems_event)
    elsif ems_event.event_type.start_with?("keypair")
      collect_key_pair_references!(target_collection, ems_event)
    end

    target_collection.targets
  end

  def parsed_targets(target_collection = {})
    target_collection.select { |_target_class, references| references[:manager_ref].present? }
  end

  def add_target(target_collection, association, ref)
    target_collection.add_target(:association => association, :manager_ref => {:ems_ref => ref})
  end

  def collect_compute_instance_references!(target_collection, ems_event)
    instance_id = ems_event.full_data.fetch_path(:content, 'payload', 'instance_id')
    add_target(target_collection, :vms, instance_id) if instance_id
  end
end
