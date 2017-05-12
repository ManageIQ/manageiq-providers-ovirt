class ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager < ManageIQ::Providers::Redhat::Inventory::Parser
  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    $rhevm_log.info("#{log_header}...")

    datacenters
    clusters
    storagedomains
    hosts
    vms

    $rhevm_log.info("#{log_header}...Complete")
  end

  def clusters
    collector.clusters.each do |cluster|
      persister.resource_pools.find_or_build(r_id).assign_attributes(
        :name       => "Default for Cluster #{cluster.name}",
        :uid_ems    => "#{cluster.id}_respool",
        :is_default => true,
      )

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(cluster.href)

      persister.clusters.find_or_build(cluster.id).assign_attributes(
        :ems_ref       => ems_ref,
        :ems_ref_obj   => ems_ref,
        :uid_ems       => cluster.id,
        :name          => cluster.name,
        :datacenter_id => persister.datacenters.lazy_find(cluster.data_center.id).id,
      )
    end
  end

  def storagedomains
    collector.storagedomains.each do |storagedomain|
      storage_type = storagedomain.dig(:storage, :type).upcase
      location = if storage_type == 'NFS' || storage_type == 'GLUSTERFS'
                   "#{storagedomain.dig(:storage, :address)}:#{storagedomain.dig(:storage, :path)}"
                 else
                   logical_units = storagedomain.dig(:storage, :volume_group, :logical_units)
                   logical_unit =  logical_units && logical_units.first
                   logical_unit && logical_unit.id
                 end

      free        = storagedomain.try(:available).to_i
      used        = storagedomain.try(:used).to_i
      total       = free + used
      committed   = storagedomain.try(:committed).to_i
      uncommitted = total - committed

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(storagedomain.try(:href))

      persister.datacenters.find_or_build(storagedomain.id).assign_attributes(
        :ems_ref             => ems_ref,
        :ems_ref_obj         => ems_ref,
        :name                => storagedomain.try(:name),
        :store_type          => storage_type,
        :storage_domain_type => storagedomain.dig(:type, :downcase),
        :total_space         => total,
        :free_space          => free,
        :uncommitted         => uncommitted,
        :multiplehostaccess  => true,
        :location            => location,
        :master              => storagedomain.try(:master)
      )
    end
  end

  def datacenters
    collector.datacenters.each do |datacenter|
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(datacenter.href)

      persister.datacenters.find_or_build(datacenter.id).assign_attributes(
        :name        => datacenter.name,
        :type        => 'Datacenter',
        :ems_ref     => ems_ref,
        :ems_ref_obj => ems_ref,
        :uid_ems     => datacenter.id,
      )
    end
  end

  def hosts
    dcs = collector.datacenters

    collector.hosts.each do |host|
      host_id = host.id

      power_state = host_inv.status
      power_state, connection_state = case power_state
                                      when 'up'             then %w(on connected)
                                      when 'maintenance'    then [power_state, 'connected']
                                      when 'down'           then %w(off disconnected)
                                      when 'non_responsive' then %w(unknown connected)
                                      else [power_state, 'disconnected']
                                      end

      hostname = host.address
      hostname = hostname.split(',').first

      nics = collector.collect_host_nics(host)
      ipaddress = host_to_ip(nics, hostname) || host.address

      ipmi_address = nil
      if host.dig(:power_management, :type).to_s.include?('ipmi')
        ipmi_address = host.dig(:power_management, :address)
      end

      host_os_version = host.dig(:os, :version)
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(host_inv.href)

      clusters = persister.clusters.lazy_find(host.dig(:cluster, :id))
      dc_ids = clusters.collect { |c| c[:datacenter_id] }.uniq
      storage_ids = []
      dcs.each do |dc|
        if dc_ids.include? dc.id
          storage_ids << collector.collect_dc_domains(dc).to_miq_a.collect { |s| s[:id] }
        end
      end

      persister_host = persister.hosts.find_or_build(host.id).assign_attributes(
        :type             => 'ManageIQ::Providers::Redhat::InfraManager::Host',
        :ems_ref          => ems_ref,
        :ems_ref_obj      => ems_ref,
        :name             => host.name || hostname,
        :hostname         => hostname,
        :ipaddress        => ipaddress,
        :uid_ems          => host_id,
        :vmm_vendor       => 'redhat',
        :vmm_product      => host.type,
        :vmm_version      => extract_host_version(host_os_version),
        :vmm_buildnumber  => (host_os_version.build if host_os_version),
        :connection_state => connection_state,
        :power_state      => power_state,
        :ems_cluster      => clusters,
        :ipmi_address     => ipmi_address,
        :storages         => storage_ids
      )

      host_operating_systems(persister_host, host, hostname)
      networks = collector.collect_networks
      switchs(persister_host, host, nics, networks)
      host_hardware(persister_host, host, networks, nics)
    end
  end

  def host_hardware(persister_host, host, networks, nics)
    hdw = host.cpu

    memory_total_attr = host.statistics.to_miq_a.detect { |stat| stat.name == 'memory.total' }
    memory_total = memory_total_attr && memory_total_attr.dig(:values, :first, :datum)
    hw_info = host.hardware_information

    cpu_cores = hdw.dig(:topology, :cores) || 1
    cpu_sockets = hdw.dig(:topology, :sockets) || 1

    persister_hardware = persister.hosts.find_or_build(persister_host).assign_attributes(
      :cpu_speed            => hdw.speed,
      :cpu_type             => hdw.name,
      :memory_mb            => memory_total.nil? ? 0 : memory_total.to_i / 1.megabyte,
      :cpu_cores_per_socket => cpu_cores,
      :cpu_sockets          => cpu_sockets,
      :cpu_total_cores      => cpu_sockets * cpu_cores,
      :manufacturer         => hw_info.manufacturer,
      :model                => hw_info.product_name
    )

    host_networks(persister_hardware, nics)
    host_guest_devices(persister_hardware, nics, networks)
  end

  def host_networks(persister_hardware, nics)
    nics.to_miq_a.each do |vnic|
      # Get the ip section
      ip = vnic.ip.presence || {}

      persister.host_nics.find_or_build(persister_hardware).assign_attributes(
        :description => vnic.name,
        :ipaddress   => ip.address,
        :subnet_mask => ip.netmask,
      )
    end
  end

  def host_guest_devices(persister_hardware, nics, networks)
    nics.to_miq_a.each do |nic|
      network = network_from_nic(nic, host, networks)

      if network
        switch_uid = network.id
      else
        switch_uid = network_name unless network_name.nil?
      end

      location = nil
      location = $1 if nic.name =~ /(\d+)$/

      persister.guest_devices.find_or_build(persister_hardware).assign_attributes(
        :uid_ems         => nic.id,
        :device_name     => nic.name,
        :device_type     => 'ethernet',
        :location        => location,
        :present         => true,
        :controller_type => 'ethernet',
        :switch          => persister.switchs.lazy_find(switch_uid),
        :network         => persister.host_nics.lazy_find(network.id)
      )
    end
  end

  def switchs(persister_host, host, nics, networks)
    nics.to_miq_a.each do |nic|
      network = network_from_nic(nic, host, networks)

      persister_switch = persister.switchs.find_or_build(persister_host).assign_attributes(
        :uid_ems => uid,
        :name    => name,
      )

      lans(persister_switch, network)
    end
  end

  def network_for_nic(nic, host, networks)
    network_id = nic.dig(:network, :id)
    if network_id
      network = networks.detect { |n| n.id == network_id }
    else
      network_name = nic.dig(:network, :name)
      cluster_id = host.dig(:cluster, :id)
      cluster = persister.clusters.lazy_find(cluster_id)
      datacenter_id = cluster.dig(:data_center, :id)
      network = networks.detect { |n| n.name == network_name && n.dig(:data_center, :id) == datacenter_id }
    end

    network
  end

  def lans(persister_switch, network)
    tag_value = nil
    if network
      uid = network.id
      name = network.name
      tag_value = network.try(:vlan).try(:id)
    else
      uid = name = network_name unless network_name.nil?
    end

    if uid.nil?
      return
    end

    persister.lans..find_or_build_by(
      :switch  => persister_switch,
      :uid_ems => uid
    ).assign_attributes(
      :name    => name,
      :uid_ems => uid,
      :tag     => tag_value
    )
  end

  def host_operating_systems(persister_host, host, hostname)
    persister.operating_systems.find_or_build_by(persister_host).assign_attributes(
      :name         => hostname,
      :product_type => 'linux',
      :product_name => extract_host_os_name(host),
      :version      => extract_host_os_full_version(host.os)
    )
  end

  def vms
    vms = Array(collector.vms) + Array(collector.templates)

    vms.each do |vm|
      # Skip the place holder template
      next if vm.id == '00000000-0000-0000-0000-000000000000'

      template = vm.href.include?('/templates/')

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(vm.href)

      host_id = vm.try(:host).try(:id)
      host_id = vm.try(:placement_policy).try(:hosts).try(:id) if host_id.blank?

      storages = storages(vm)

      persister_vm = persister.vms.find_or_build(vm.id).assign_attributes(
        :type             => template ? "ManageIQ::Providers::Redhat::InfraManager::Template" : "ManageIQ::Providers::Redhat::InfraManager::Vm",
        :ems_ref          => ems_ref,
        :ems_ref_obj      => ems_ref,
        :uid_ems          => vm.id,
        :connection_state => "connected",
        :vendor           => "redhat",
        :name             => URI.decode(vm.name),
        :location         => "#{vm.id}.ovf",
        :template         => template,
        :memory_reserve   => vm_memory_reserve(vm),
        :raw_power_state  => template ? "never" : vm.status,
        :boot_time        => vm.try(:start_time),
        :host             => persister.hosts.lazy_find(host_id),
        :ems_cluster      => persister.clusters.lazy_find(vm.cluster.id),
        :storages         => storages,
        :storage          => storages.first,
      )

      vm_hardware(persister_vm, vm)
      snapshots(persister_vm, vm)
      operating_systems(persister_vm, vm)
      custom_attributes(persister_vm, vm)
    end
  end

  def storages(vm)
    storages = []
    collector.attached_disks(vm).to_miq_a.each do |disk|
      disk.storage_domains.to_miq_a.each do |sd|
        storages << persister.storages.lazy_find(:ems_ref => sd.id)
      end
    end
    storages.compact!
    storages.uniq!

    storages
  end

  def vm_hardware(presister_vm, vm)
    topology = vm.cpu.topology
    cpu_socks = topology.try(:sockets) || 1
    cpu_cores = topology.try(:cores) || 1

    result[:memory_mb] = vm.memory / 1.megabyte

    persister_hardware = persister.hardwares.find_or_build(presister_vm).assign_attributes(
      :guest_os             => vm.dig(:os, :type),
      :annotation           => vm.try(:description),
      :cpu_cores_per_socket => cpu_socks,
      :cpu_sockets          => cpu_cores,
      :cpu_total_cores      => cpu_cores * cpu_socks,
      :memory_mb            => vm.memory / 1.megabyte
    )

    hardware_disks(persister_hardware, vm)
    addresses = hardware_networks(persister_hardware, vm)
    hardware_guest_devices(persister_hardware, vm, addresses)
  end

  def hardware_networks(persister_hardware, vm)
    devices = collector.collect_vm_devices(vm)
    device = devices[0]

    nets = device.ips if device
    if nets.nil?
      return
    end

    addresses = []

    nets.to_miq_a.each do |net|
      addresses << net.address
      persister.nics.find_or_build_by(
        :hardware  => persister_hardware,
        :ipaddress => net.address
      ).assign_attributes(
        :ipaddress => net.address,
        :hostname  => net.fqdn
      )
    end
    addresses
  end

  def hardware_disks(persister_hardware, vm)
    disks = collector.collect_attached_disks(vm)

    disks = disks.to_miq_a.sort_by do |disk|
      match = disk.try(:name).match(/disk[^\d]*(?<index>\d+)/i)
      [disk.try(:bootable) ? 0 : 1, match ? match[:index].to_i : Float::INFINITY, disk.name]
    end.group_by { |d| d.try(:interface) }

    disks.each do |interface, devices|
      devices.each_with_index do |device, index|
        storage_domain = device.storage_domains && device.storage_domains.first
        storage_id = storage_domain && storage_domain.id

        persister.disks.find_or_build_by(
          :hardware    => persister_hardware,
          :device_name => device.name
        ).assign_attributes(
          :device_name     => device.name,
          :device_type     => 'disk',
          :controller_type => interface,
          :present         => true,
          :filename        => device.id,
          :location        => index.to_s,
          :size            => device.provisioned_size.to_i,
          :size_on_disk    => device.actual_size.to_i,
          :disk_type       => device.sparse == true ? 'thin' : 'thick',
          :mode            => 'persistent',
          :bootable        => device.try(:bootable),
          :storage         => persister.storages.lazy_find(:ems_ref => storage_id)
        )
      end
    end
  end

  def hardware_guest_devices(persister_hardware, vm, addresses)
    collector.collect_nics(vm).each do |nic|
      persister.guest_devices.find_or_build_by(
        :hardware => persister_hardware,
        :uid_ems  => nic.id
      ).assign_attributes(
        :uid_ems         => nic.id,
        :device_name     => nic.name,
        :device_type     => 'ethernet',
        :controller_type => 'ethernet',
        :address         => nic.dig(:mac, :address),
        :lan             => nic.dig(:network, :id),
        :network         => persister.nics.lazy_find(addresses[0])
      )
    end
  end

  def snapshots(persister_vm, vm)
    snapshots = collector.collect_snapshots(vm)
    parent_id = nil
    snapshots.each_with_index do |snapshot, idx|
      name = description = snapshot.description
      name = "Active Image" if name[0, 13] == '_ActiveImage_'

      persister.snapshots.find_or_build_by(persister_vm).assign_attributes(
        :uid_ems     => snapshot.id,
        :uid         => snapshot.id,
        :parent_uid  => parent_id,
        :name        => name,
        :description => description,
        :create_time => snapshot.date.getutc,
        :current     => idx == snapshots.length - 1,
      )
      parent_id = snapshot.id
    end
  end

  def operating_systems(persister_vm, vm)
    guest_os = vm.dig(:os, :type)

    persister.operating_systems.find_or_build_by(persister_vm).assign_attributes(
      :product_name => guest_os.blank? ? "Other" : guest_os,
      :system_type  => vm.type
    )
  end

  def custom_attributes(persister_vm, vm)
    custom_attrs = vm.try(:custom_properties)
    return result if custom_attrs.nil?

    custom_attrs.each do |ca|
      persister.custom_attributes.find_or_build_by(persister_vm).assign_attributes(
        :section => 'custom_field',
        :name    => ca.name,
        :value   => ca.value.try(:truncate, 255),
        :source  => "VC",
      )
    end
  end

  private

  require 'ostruct'

  def vm_memory_reserve(vm)
    in_bytes = vm.dig(:memory_policy, :guaranteed)
    in_bytes.nil? ? nil : in_bytes / Numeric::MEGABYTE
  end

  def host_to_ip(nics, hostname = nil)
    ipaddress = nil
    nics.to_miq_a.each do |nic|
      ip_data = nic.ip
      if !ip_data.nil? && !ip_data.gateway.blank? && !ip_data.address.blank?
        ipaddress = ip_data.address
        break
      end
    end

    unless ipaddress.nil?
      unless [nil, "localhost", "localhost.localdomain", "127.0.0.1"].include?(hostname)
        begin
          ipaddress = Socket.getaddrinfo(hostname, nil)[0][3]
        rescue => err
          $rhevm_log.warn "IP lookup by hostname [#{hostname}]...Failed with the following error: #{err}"
        end
      end
    end

    ipaddress
  end

  def extract_host_version(host_os_version)
    return unless host_os_version && host_os_version.major

    version = host_os_version.major
    version = "#{version}.#{host_os_version.minor}" if host_os_version.minor
    version
  end

  def extract_host_os_name(host)
    host_os = host.os
    host_os && host_os.type || host.type
  end

  def extract_host_os_full_version(host_os)
    host_os.dig(:version, :full_version)
  end
end
