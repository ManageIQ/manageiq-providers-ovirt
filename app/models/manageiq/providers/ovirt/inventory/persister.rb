class ManageIQ::Providers::Ovirt::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :InfraManager
  require_nested :TargetCollection
end
