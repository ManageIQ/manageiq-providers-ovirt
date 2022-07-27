class ManageIQ::Providers::Ovirt::InfraManager::ExternalDistributedVirtualSwitch < ManageIQ::Providers::InfraManager::DistributedVirtualSwitch
  belongs_to :ext_management_system, :foreign_key => :ems_id, :inverse_of => :external_distributed_virtual_switches, :class_name => "ManageIQ::Providers::Ovirt::InfraManager"

  include RelationshipMixin
  self.default_relationship_type = "ems_metadata"

  def parent_datacenter
    detect_ancestor(:of_type => "EmsFolder") { |a| a.kind_of?(Datacenter) }
  end
end
