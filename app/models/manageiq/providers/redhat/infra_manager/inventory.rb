class ManageIQ::Providers::Redhat::InfraManager::Inventory
  attr_accessor :connection
  attr_reader :ems

  VERSION_HASH = {:version => 4}.freeze

  def initialize(args)
    @ems = args[:ems]
  end

  TOP_LEVEL_INVENTORY_TYPES = %w[cluster storage host vm template network datacenter disk vnic_profile].freeze

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
      collect_snapshots_total_size(res[:vm])
      collect_disks_from_attachments(res[:template], preloaded_disks)
      res
    end
  end

  def collect_snapshots_total_size(vms)
    vms.each do |vm|
      ManageIQ::Providers::Redhat::Inventory::Collector.add_snapshot_disks_total_size(connection, vm.snapshots, vm.id)
    end
  end

  def collect_disks_from_attachments(inv, preloaded_disks)
    inv.each do |inv_item|
      disks = DisksHelper.collect_attached_disks(inv_item, connection, preloaded_disks)
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

  def collect_disks_as_hash(disks = nil)
    DisksHelper.collect_disks_as_hash(connection, disks)
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
end
