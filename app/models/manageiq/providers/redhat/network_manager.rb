class ManageIQ::Providers::Redhat::NetworkManager < ManageIQ::Providers::NetworkManager
  require_nested :CloudNetwork
  require_nested :CloudSubnet
  require_nested :EventCatcher
  require_nested :EventParser
  require_nested :FloatingIp
  require_nested :NetworkPort
  require_nested :NetworkRouter
  require_nested :RefreshWorker
  require_nested :Refresher
  require_nested :SecurityGroup

  include ManageIQ::Providers::Openstack::ManagerMixin
  include SupportsFeatureMixin

  supports :create
  supports :port

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
    @ems_type ||= "redhat_network".freeze
  end

  def self.description
    @description ||= "Redhat Network".freeze
  end

  def self.default_blacklisted_event_names
    %w(
      scheduler.run_instance.start
      scheduler.run_instance.scheduled
      scheduler.run_instance.end
    )
  end

  def supports_api_version?
    true
  end

  def supports_security_protocol?
    true
  end

  def supported_auth_types
    %w(default amqp)
  end

  def supports_provider_id?
    true
  end

  def supports_authentication?(authtype)
    supported_auth_types.include?(authtype.to_s)
  end

  def self.event_monitor_class
    ManageIQ::Providers::Redhat::NetworkManager::EventCatcher
  end

  def create_cloud_network(options)
    CloudNetwork.raw_create_cloud_network(self, options)
  end

  def create_cloud_network_queue(userid, options = {})
    task_opts = {
      :action => "creating Cloud Network for user #{userid}",
      :userid => userid
    }
    queue_opts = {
      :class_name  => self.class.name,
      :method_name => 'create_cloud_network',
      :instance_id => id,
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [options]
    }
    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def create_cloud_subnet(options)
    CloudSubnet.raw_create_cloud_subnet(self, options)
  end

  def create_network_router(options)
    NetworkRouter.raw_create_network_router(self, options)
  end

  def create_network_router_queue(userid, options = {})
    task_opts = {
      :action => "creating Network Router for user #{userid}",
      :userid => userid
    }
    queue_opts = {
      :class_name  => self.class.name,
      :method_name => 'create_network_router',
      :instance_id => id,
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [options]
    }
    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def create_floating_ip(options)
    FloatingIp.raw_create_floating_ip(self, options)
  end

  def create_floating_ip_queue(userid, options = {})
    task_opts = {
      :action => "creating Floating IP for user #{userid}",
      :userid => userid
    }
    queue_opts = {
      :class_name  => self.class.name,
      :method_name => 'create_floating_ip',
      :instance_id => id,
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [options]
    }
    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def create_security_group(options)
    SecurityGroup.raw_create_security_group(self, options)
  end

  def create_security_group_queue(userid, options = {})
    task_opts = {
      :action => "creating Security Group for user #{userid}",
      :userid => userid
    }
    queue_opts = {
      :class_name  => self.class.name,
      :method_name => 'create_security_group',
      :instance_id => id,
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [options]
    }
    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def tenants
    @tenants ||= openstack_handle.tenants
  end
end
