class ManageIQ::Providers::Redhat::InfraManager::Datacenter < ManageIQ::Providers::InfraManager::Datacenter
  def distributed_virtual_switches
    children(:of_type => 'Switch')
  end

  def external_distributed_virtual_switches
    distributed_virtual_switches.select do |s|
      s.kind_of?(ManageIQ::Providers::Redhat::InfraManager::ExternalDistributedVirtualSwitch)
    end
  end

  def external_distributed_virtual_lans
    external_distributed_virtual_switches.map(&:lans).flatten
  end
end
