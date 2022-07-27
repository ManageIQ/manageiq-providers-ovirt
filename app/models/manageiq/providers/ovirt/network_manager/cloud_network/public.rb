class ManageIQ::Providers::Ovirt::NetworkManager::CloudNetwork::Public < ManageIQ::Providers::Ovirt::NetworkManager::CloudNetwork
  def self.display_name(number = 1)
    n_('External Cloud Network (oVirt)', 'External Cloud Networks (oVirt)', number)
  end
end
