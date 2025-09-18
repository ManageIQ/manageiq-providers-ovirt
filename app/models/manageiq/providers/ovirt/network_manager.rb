class ManageIQ::Providers::Ovirt::NetworkManager < ManageIQ::Providers::NetworkManager
  include ManageIQ::Providers::Openstack::ManagerMixin
  include SupportsFeatureMixin

  supports :create_network_router
  supports :cloud_subnet_create

  has_many :public_networks,  :foreign_key => :ems_id, :dependent => :destroy,
           :class_name => "ManageIQ::Providers::Openstack::NetworkManager::CloudNetwork::Public"
  has_many :private_networks, :foreign_key => :ems_id, :dependent => :destroy,
           :class_name => "ManageIQ::Providers::Openstack::NetworkManager::CloudNetwork::Private"

  delegate :zone,
           :guest_devices,
           :authentication_check, # TODO: fix it, auth shouldn't be done via the parent
           :authentication_status,
           :authentication_status_ok?,
           :authentications,
           :authentication_for_summary,
           :to        => :parent_manager,
           :allow_nil => true

  def self.hostname_required?
    false
  end

  def self.ems_type
    @ems_type ||= "ovirt_network".freeze
  end

  def self.description
    @description ||= "oVirt Network".freeze
  end

  def supported_auth_types
    %w(default amqp)
  end

  def create_cloud_network(options)
    CloudNetwork.raw_create_cloud_network(self, options)
  end

  def create_cloud_subnet(options)
    CloudSubnet.raw_create_cloud_subnet(self, options)
  end

  def create_network_router(options)
    NetworkRouter.raw_create_network_router(self, options)
  end

  def create_floating_ip(options)
    FloatingIp.raw_create_floating_ip(self, options)
  end

  def create_security_group(options)
    SecurityGroup.raw_create_security_group(self, options)
  end

  def tenants
    @tenants ||= openstack_handle.tenants
  end
end
