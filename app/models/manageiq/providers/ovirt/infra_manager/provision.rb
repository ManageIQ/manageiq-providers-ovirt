class ManageIQ::Providers::Ovirt::InfraManager::Provision < MiqProvision
  include_concern 'Cloning'
  include_concern 'Configuration'
  include_concern 'Placement'
  include_concern 'StateMachine'
  include_concern 'Disk'

  def destination_type
    "Vm"
  end

  def with_provider_destination
    return if destination.nil?
    destination.with_provider_object { |obj| yield obj }
  end
end
