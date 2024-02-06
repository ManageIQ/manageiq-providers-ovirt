class ManageIQ::Providers::Ovirt::InfraManager::Provision < MiqProvision
  include Cloning
  include Configuration
  include Placement
  include StateMachine
  include Disk

  def destination_type
    "Vm"
  end

  def with_provider_destination
    return if destination.nil?
    destination.with_provider_object { |obj| yield obj }
  end
end
