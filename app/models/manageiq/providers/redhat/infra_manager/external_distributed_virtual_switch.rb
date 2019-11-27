class ManageIQ::Providers::Redhat::InfraManager::ExternalDistributedVirtualSwitch < ManageIQ::Providers::InfraManager::DistributedVirtualSwitch
  belongs_to :ext_management_system, :foreign_key => :ems_id, :inverse_of => :external_distributed_virtual_switches, :class_name => "ManageIQ::Providers::Redhat::InfraManager"
end
