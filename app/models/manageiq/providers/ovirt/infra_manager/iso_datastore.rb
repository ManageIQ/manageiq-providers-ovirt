class ManageIQ::Providers::Ovirt::InfraManager::IsoDatastore < ManageIQ::Providers::Ovirt::InfraManager::Storage
  belongs_to :ext_management_system, :foreign_key => :ems_id

  def self.display_name(number = 1)
    n_('ISO Datastore', 'ISO Datastores', number)
  end
end
