class ManageIQ::Providers::Redhat::InfraManager::Datacenter < ManageIQ::Providers::InfraManager::Datacenter
  def distributed_virtual_switches
    children(:of_type => 'Switch')
  end

  alias add_distributed_virtual_switch set_child
  alias remove_distributed_virtual_switch remove_child
end
