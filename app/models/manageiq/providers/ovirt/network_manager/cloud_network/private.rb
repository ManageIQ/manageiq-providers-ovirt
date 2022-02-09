class ManageIQ::Providers::Ovirt::NetworkManager::CloudNetwork::Private < ManageIQ::Providers::Ovirt::NetworkManager::CloudNetwork
  def self.display_name(number = 1)
    n_('Cloud Network (oVirt)', 'Cloud Networks (oVirt)', number)
  end
end
