class ManageIQ::Providers::Redhat::NetworkManager::CloudNetwork::Public < ManageIQ::Providers::Redhat::NetworkManager::CloudNetwork
  def self.display_name(number = 1)
    n_('External Cloud Network (Ovirt)', 'External Cloud Networks (Ovirt)', number)
  end
end
