module ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies
  class V4
    attr_accessor :connection
    attr_reader :ems

    VERSION_HASH = {:version => 4}.freeze

    def initialize(args)
      @ems = args[:ems]
    end

    def host_targeted_refresh(target)
      ems.with_provider_connection(VERSION_HASH) do |connection|
        @connection = connection
        res = {}
        res[:cluster] = collect_cluster(get_uuid_from_target(target.ems_cluster))
        res[:host] = collect_host(get_uuid_from_target(target))
        res[:network] = collect_networks
        res
      end
    end

    def template_targeted_refresh(target)
      ems.with_provider_connection(VERSION_HASH) do |connection|
        @connection = connection
        template_id = get_uuid_from_target(target)
        res = {}
        res[:cluster] = collect_clusters
        res[:datacenter] = collect_datacenters
        res[:template] = collect_template_by_uuid(template_id)
        res[:storage] = target.storages.empty? ? collect_storages : collect_storage(target.storages.map { |s| get_uuid_from_target(s) })
        res
      end
    end

    def vm_targeted_refresh(target)
      ems.with_provider_connection(VERSION_HASH) do |connection|
        @connection = connection
        vm_id = get_uuid_from_target(target)
        res = {}
        res[:cluster] = collect_clusters
        res[:datacenter] = collect_datacenters
        res[:vm] = collect_vm_by_uuid(vm_id)
        res[:storage] = target.storages.empty? ? collect_storages : collect_storage(target.storages.map { |s| get_uuid_from_target(s) })
        res[:template] = search_templates("vm.id=#{vm_id}")
        res
      end
    end

    def get_uuid_from_href(ems_ref)
      URI(ems_ref).path.split('/').last
    end

    def get_uuid_from_target(object)
      get_uuid_from_href(object.ems_ref)
    end

    TOP_LEVEL_INVENTORY_TYPES = %w(cluster storage host vm template network datacenter disk)

    # This hash contains the attributes to be fetched for diffrent types of inventory.
    ATTRIBUTES_TO_FETCH_FOR_INV_TYPE = {
      :host        => [:nics, :statistics],
      :data_center => [:storage_domains],
      :vm          => [:nics, :reported_devices, :snapshots, :disk_attachments],
      :template    => [:disk_attachments]
    }.freeze

    def refresh
      ems.with_provider_connection(VERSION_HASH) do |connection|
        @connection = connection
        top_level_futures_hash = collect_top_level_futures
        res = wait_on_top_level_collections(top_level_futures_hash)
        res.each { |inv_name, inv| res[inv_name] = collect_inv_with_attributes_async(inv, inv_name_to_inv_type(inv_name)) }
        preloaded_disks = collect_disks_as_hash(res[:disk])
        collect_disks_from_attachments(res[:vm], preloaded_disks)
        collect_disks_from_attachments(res[:template], preloaded_disks)
        res
      end
    end

    def collect_disks_from_attachments(inv, preloaded_disks)
      inv.each do |inv_item|
        disks = AttachedDisksFetcher.attached_disks(inv_item, connection, preloaded_disks)
        inv_item.singleton_class.send(:attr_accessor, :disks)
        inv_item.disks = disks
      end
    end

    def collect_inv_with_attributes_async(inv, inv_type)
      return inv if ATTRIBUTES_TO_FETCH_FOR_INV_TYPE[inv_type].blank?
      inv_keyed_requests = collect_inv_attributes_request(inv, inv_type)
      inv_fetched_attributes = ManageIQ::Providers::Redhat::InfraManager::FuturesCollector.process_keyed_requests_queue(inv_keyed_requests)
      raise "Failed to fetch attributes for #{inv_type}" unless inv_fetched_attributes
      set_inv_attributes!(inv, inv_fetched_attributes, inv_type)
    end

    def set_inv_attributes!(inv, inv_fetched_attributes, inv_type)
      inv.each do |obj|
        key = base_key_for_obj(obj, inv_type)
        ATTRIBUTES_TO_FETCH_FOR_INV_TYPE[inv_type].each do |attribute_name|
          obj.instance_variable_set("@#{attribute_name}", inv_fetched_attributes["#{key}#{attribute_name}"])
        end
      end
    end

    def collect_inv_attributes_request(objs, obj_type)
      obj_requests = []
      objs.each do |obj|
        ATTRIBUTES_TO_FETCH_FOR_INV_TYPE[obj_type].each do |attribute_name|
          obj_requests << obj_attribute_request(obj, obj_type, attribute_name)
        end
      end
      obj_requests
    end

    def wait_on_top_level_collections(top_level_futures_hash)
      top_level_futures_hash.each do |k, v|
        top_level_futures_hash[k] = v.wait
      end
      top_level_futures_hash
    end

    def collect_top_level_futures
      res = {}
      TOP_LEVEL_INVENTORY_TYPES.each { |inv_name| res[inv_name.to_sym] = collect_inv_future(inv_name.to_sym) }
      res
    end

    def collect_inv_future(inv_name)
      inv_type = inv_name_to_inv_type(inv_name)
      connection.system_service.send("#{inv_type}s_service").list(:wait => false)
    end

    def inv_name_to_inv_type(inv_name)
      case inv_name
      when :datacenter
        :data_center
      when :storage
        :storage_domain
      else
        inv_name.to_sym
      end
    end

    def collect_clusters
      connection.system_service.clusters_service.list
    end

    def collect_cluster(uuid)
      Array(connection.system_service.clusters_service.cluster_service(uuid).get)
    end

    def collect_storages
      connection.system_service.storage_domains_service.list
    end

    def collect_storage(uuids)
      uuids.collect do |uuid|
        connection.system_service.storage_domains_service.storage_domain_service(uuid).get
      end
    end

    def collect_hosts
      connection.system_service.hosts_service.list.collect do |h|
        HostPreloadedAttributesDecorator.new(h, connection)
      end
    end

    def collect_host(uuid)
      host = connection.system_service.hosts_service.host_service(uuid).get
      [HostPreloadedAttributesDecorator.new(host, connection)]
    rescue OvirtSDK4::Error
      []
    end

    def collect_vms
      connection.system_service.vms_service.list.collect do |vm|
        VmPreloadedAttributesDecorator.new(vm, connection, preloaded_disks)
      end
    end

    def preloaded_disks
      @preloaded_disks ||= collect_disks_as_hash
    end

    def collect_disks_as_hash(disks = nil)
      disks ||= connection.system_service.disks_service.list
      Hash[disks.collect { |d| [d.id, d] }]
    end

    def collect_future_vm_disk_attachments(vms, vms_service)
      vms_attachments = vms.collect do |vm|
        vm_service = vms_service.vm_service(vm.id)
        disk_attachments_service = vm_service.disk_attachments_service
        disk_attachments_future = disk_attachments_service.list(:wait => false)
        [vm.id, disk_attachments_future]
      end
      Hash[vms_attachments]
    end

    def collect_vm_by_uuid(uuid)
      vm = connection.system_service.vms_service.vm_service(uuid).get
      [VmPreloadedAttributesDecorator.new(vm, connection)]
    rescue OvirtSDK4::Error
      []
    end

    def collect_template_by_uuid(uuid)
      template = connection.system_service.templates_service.template_service(uuid).get
      [TemplatePreloadedAttributesDecorator.new(template, connection)]
    rescue OvirtSDK4::Error
      []
    end

    def collect_templates_future
      connection.system_service.templates_service.list(:wait => false)
    end

    def base_key_for_obj(obj, obj_type)
      "#{obj_type}_#{obj.id}_"
    end

    def obj_attribute_request(obj, obj_type, attr_name)
      objs_service = connection.system_service.send("#{obj_type}s_service")
      procedure = proc do
        objs_service.send("#{obj_type}_service", obj.id).send("#{attr_name}_service").list(:wait => false)
      end
      key = "#{base_key_for_obj(obj, obj_type)}#{attr_name}"
      { key => procedure}
    end

    def collect_templates
      connection.system_service.templates_service.list.collect do |template|
        TemplatePreloadedAttributesDecorator.new(template, connection, preloaded_disks)
      end
    end

    def collect_future_template_disk_attachments(templates, templates_service)
      templates_attachments = templates.collect do |template|
        template_service = templates_service.template_service(template.id)
        atts_service = template_service.disk_attachments_service
        atts_future = atts_service.list(:wait => false)
        [template.id, atts_future]
      end
      Hash[templates_attachments]
    end

    def search_templates(search)
      connection.system_service.templates_service.list(:search => search).collect do |template|
        TemplatePreloadedAttributesDecorator.new(template, connection, preloaded_disks)
      end
    end

    def collect_networks
      connection.system_service.networks_service.list
    end

    def collect_datacenters
      connection.system_service.data_centers_service.list.collect do |datacenter|
        DatacenterPreloadedAttributesDecorator.new(datacenter, connection)
      end
    end

    def api
      ems.with_provider_connection(VERSION_HASH) do |connection|
        connection.system_service.get.product_info.version.full_version
      end
    end

    def service
      ems.with_provider_connection(VERSION_HASH) do |connection|
        OpenStruct.new(:version_string => connection.system_service.get.product_info.version.full_version)
      end
    end

    class HostPreloadedAttributesDecorator < SimpleDelegator
      attr_reader :nics, :statistics
      def initialize(host, connection)
        @obj = host
        @nics = connection.follow_link(host.nics)
        @statistics = connection.link?(host.statistics) ? connection.follow_link(host.statistics) : host.statistics
        super(host)
      end
    end

    class DatacenterPreloadedAttributesDecorator < SimpleDelegator
      attr_reader :storage_domains
      def initialize(datacenter, connection)
        @obj = datacenter
        @storage_domains = connection.follow_link(datacenter.storage_domains)
        super(datacenter)
      end
    end

    class VmPreloadedAttributesDecorator < SimpleDelegator
      attr_reader :disks, :nics, :reported_devices, :snapshots
      def initialize(vm, connection, preloaded_disks = nil)
        @obj = vm
        @disks = self.class.get_attached_disks_from_futures(vm, connection, preloaded_disks)
        @nics = connection.follow_link(vm.nics)
        @reported_devices = connection.follow_link(vm.reported_devices)
        @snapshots = connection.follow_link(vm.snapshots)
        super(vm)
      end

      def self.get_attached_disks_from_futures(vm, connection, preloaded_disks = nil)
        AttachedDisksFetcher.get_attached_disks_from_futures(vm, connection, preloaded_disks)
      end
    end

    class AttachedDisksFetcher
      def self.get_attached_disks_from_futures(disks_owner, connection, preloaded_disks = nil, future_disk_attachments = nil)
        attachments = future_disk_attachments ? future_disk_attachments.wait : connection.follow_link(disks_owner.disk_attachments)
        attachments.map do |attachment|
          res = disk_from_attachment(connection, attachment, preloaded_disks)
          res.interface = attachment.interface
          res.bootable = attachment.bootable
          res.active = attachment.active
          res
        end
      end

      def self.attached_disks(disks_owner, connection, preloaded_disks)
        disks_owner.disk_attachments.map do |attachment|
          res = disk_from_attachment(connection, attachment, preloaded_disks)
          res.interface = attachment.interface
          res.bootable = attachment.bootable
          res.active = attachment.active
          res
        end
      end

      def self.disk_from_attachment(connection, attachment, preloaded_disks)
        disk = preloaded_disks && preloaded_disks[attachment.disk.id]
        disk || connection.follow_link(attachment.disk)
      end
    end

    class TemplatePreloadedAttributesDecorator < SimpleDelegator
      attr_reader :disks
      def initialize(template, connection, preloaded_disks = nil)
        @obj = template
        @disks = AttachedDisksFetcher.get_attached_disks_from_futures(template, connection, preloaded_disks, nil)
        super(template)
      end
    end
  end
end
