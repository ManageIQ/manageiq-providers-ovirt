class ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager < ManageIQ::Providers::Redhat::Inventory::Parser
  # TODO: review the changes here and find common parts with ManageIQ::Providers::Redhat::InfraManager::Refresh::Parse::*
  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    $rhevm_log.info("#{log_header}...")

    ems_clusters
    datacenters
    storagedomains
    hosts
    vms

    $rhevm_log.info("#{log_header}...Complete")
  end

  def ems_clusters
    collector.ems_clusters.each do |cluster|
      r_id = "#{cluster.id}_respool"

      persister.resource_pools.find_or_build(:ems_uid => r_id).assign_attributes(
        :name       => "Default for Cluster #{cluster.name}",
        :uid_ems    => r_id,
        :is_default => true,
      )

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(cluster.href)

      persister.ems_clusters.build(
        :ems_ref       => ems_ref,
        :ems_ref_obj   => ems_ref,
        :uid_ems       => cluster.id,
        :name          => cluster.name,
        :datacenter_id => cluster.dig(:data_center, :id),
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

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(storagedomain.try(:href))

      persister.storages.find_or_build(ems_ref).assign_attributes(
        :ems_ref             => ems_ref,
        :ems_ref_obj         => ems_ref,
        :name                => storagedomain.try(:name),
        :store_type          => storage_type,
        :storage_domain_type => storagedomain.dig(:type, :downcase),
        :total_space         => total,
        :free_space          => free,
        :uncommitted         => total - committed,
        :multiplehostaccess  => true,
        :location            => location,
        :master              => storagedomain.try(:master)
      )
    end
  end

  def datacenters
    collector.datacenters.each do |datacenter|
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(datacenter.href)

      persister.ems_folders.find_or_build('root_dc').assign_attributes(
        :name    => 'Datacenters',
        :type    => 'EmsFolder',
        :uid_ems => 'root_dc',
        :hidden  => true,
        :parent  => nil,
      )

      uid = datacenter.id
      persister.datacenters.find_or_build(ems_ref).assign_attributes(
        :name        => datacenter.name,
        :type        => 'Datacenter',
        :ems_ref     => ems_ref,
        :ems_ref_obj => ems_ref,
        :uid_ems     => uid,
        :parent      => persister.ems_folders.lazy_find("root_dc"),
      )

      host_folder_uid = "#{uid}_host"
      persister.ems_folders.find_or_build(host_folder_uid).assign_attributes(
        :name    => 'host',
        :type    => 'EmsFolder',
        :uid_ems => host_folder_uid,
        :hidden  => true,
        :parent  => persister.datacenters.lazy_find(ems_ref),
      )

      vm_folder_uid = "#{uid}_vm"
      persister.ems_folders.find_or_build(vm_folder_uid).assign_attributes(
        :name    => 'vm',
        :type    => 'EmsFolder',
        :uid_ems => vm_folder_uid,
        :hidden  => true,
        :parent  => persister.datacenters.lazy_find(ems_ref),
      )
    end
  end

  def hosts
    collector.hosts.each do |host|
      host_id = host.id

      power_state = host.status
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

      host_os_version = host.dig(:os, :version)
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(host.href)

      cluster = collector.collect_cluster_for_host(host)
      dc = collector.collect_datacenter_for_cluster(cluster)
      persister_host = persister.hosts.find_or_build(ems_ref).assign_attributes(
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
        :maintenance      => power_state == 'maintenance',
        :ems_cluster      => persister.ems_clusters.lazy_find({:uid_ems => cluster.id}, :ref => :by_uid_ems),
      )

      host_storages(dc, persister_host)
      host_operating_systems(persister_host, host, hostname)
      networks = collector.collect_networks
      switches(persister_host, dc, nics, networks)
      host_hardware(persister_host, host, networks, nics)
    end
  end

  def host_storages(dc, persister_host)
    storages = []
    collector.collect_dc_domains(dc).to_miq_a.each do |sd|
      ems_href = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(sd.href)
      # we need to trim datacenter part of href
      storages << persister.storages.lazy_find(ems_href[0..4] + ems_href[54..-1])
    end
    storages.compact!
    storages.uniq!

    storages.each do |storage|
      persister.host_storages.find_or_build_by(
        :host    => persister_host,
        :storage => storage
      ).assign_attributes(
        :host    => persister_host,
        :storage => storage
      )
    end
  end

  def host_hardware(persister_host, host, networks, nics)
    hdw = host.cpu

    stats = collector.collect_host_stats(host)
    memory_total_attr = stats.to_miq_a.detect { |stat| stat.name == 'memory.total' }
    memory_total = memory_total_attr && memory_total_attr.dig(:values, :first, :datum)
    hw_info = host.hardware_information

    cpu_cores = hdw.dig(:topology, :cores) || 1
    cpu_sockets = hdw.dig(:topology, :sockets) || 1

    persister_hardware = persister.host_hardwares.find_or_build(persister_host).assign_attributes(
      :cpu_speed            => hdw.speed,
      :cpu_type             => hdw.name,
      :memory_mb            => memory_total.nil? ? 0 : memory_total.to_i / 1.megabyte,
      :cpu_cores_per_socket => cpu_cores,
      :cpu_sockets          => cpu_sockets,
      :cpu_total_cores      => cpu_sockets * cpu_cores,
      :manufacturer         => hw_info.manufacturer,
      :model                => hw_info.product_name,
      :serial_number        => hw_info.serial_number,
      :number_of_nics       => nics.count
    )

    host_guest_devices(persister_hardware, host, nics, networks)
  end

  def host_guest_devices(persister_hardware, host, nics, networks)
    persister_host = persister_hardware.host

    nics.to_miq_a.each do |nic|
      network = network_from_nic(nic, host, networks)
      ip = nic.ip.presence || nil

      location = nil
      location = $1 if nic.name =~ /(\d+)$/

      persister_nic = persister.host_networks.find_or_build_by(
        :hardware  => persister_hardware,
        :ipaddress => ip&.address
      ).assign_attributes(
        :description => nic.name,
        :ipaddress   => ip&.address,
        :subnet_mask => ip&.netmask,
      )

      attributes = {
        :uid_ems         => nic.id,
        :device_name     => nic.name,
        :device_type     => 'ethernet',
        :location        => location,
        :present         => true,
        :controller_type => 'ethernet'
      }

      unless network.nil?
        switch_uid = network.try(:id) || network.name
        attributes[:switch] = persister.host_virtual_switches.lazy_find(:host => persister_host, :uid_ems => switch_uid)
        attributes[:network] = persister_nic
      end

      persister.host_guest_devices.find_or_build_by(
        :hardware => persister_hardware,
        :uid_ems  => nic.id
      ).assign_attributes(attributes)
    end
  end

  def switches(persister_host, dc, nics, networks)
    nics.to_miq_a.each do |nic|
      network = network_from_nic(nic, dc, networks)

      next if network.nil?

      uid = network.try(:id) || network.name
      name = network.name

      persister_switch = persister.host_virtual_switches.find_or_build_by(
        :host => persister_host, :uid_ems => uid
      ).assign_attributes(
        :host    => persister_host,
        :uid_ems => uid,
        :name    => name,
      )

      lans(network, persister_switch)

      persister.host_switches.find_or_build_by(
        :host   => persister_host,
        :switch => persister_switch
      ).assign_attributes(
        :host   => persister_host,
        :switch => persister_switch
      )
    end
  end

  def network_from_nic(nic, dc, networks)
    return unless dc
    network_id = nic.dig(:network, :id)
    if network_id
      # TODO: check to indexed_networks = networks.index_by(:id)
      network = networks.detect { |n| n.id == network_id }
    else
      network_name = nic.dig(:network, :name)
      if network_name
        network = networks.detect { |n| n.name == network_name && n.dig(:data_center, :id) == dc.id }
      end
    end

    network
  end

  def lans(network, persister_switch)
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

    persister.lans.find_or_build_by(
      :switch => persister_switch, :uid_ems => uid
    ).assign_attributes(
      :name    => name,
      :uid_ems => uid,
      :tag     => tag_value,
      :switch  => persister_switch,
    )
  end

  def host_operating_systems(persister_host, host, hostname)
    persister.host_operating_systems.find_or_build(persister_host).assign_attributes(
      :name         => hostname,
      :product_type => 'linux',
      :product_name => extract_host_os_name(host),
      :version      => extract_host_os_full_version(host.os)
    )
  end

  def vms
    vms = Array(collector.vms) + Array(collector.templates)
    vms.compact.each do |vm|
      # Skip the place holder template
      next if vm.id == '00000000-0000-0000-0000-000000000000'

      template = vm.href.include?('/templates/')

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(vm.href)

      host = vm.try(:host) || vm.try(:placement_policy).try(:hosts).try(:first)
      host_ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(host.href) if host.present?

      storages, disks = storages(vm)

      collection_persister = if template
                               persister.miq_templates
                             else
                               persister.vms
                             end
      persister_vm = collection_persister.find_or_build(vm.id).assign_attributes(
        :type             => template ? "ManageIQ::Providers::Redhat::InfraManager::Template" : "ManageIQ::Providers::Redhat::InfraManager::Vm",
        :ems_ref          => ems_ref,
        :ems_ref_obj      => ems_ref,
        :uid_ems          => vm.id,
        :connection_state => "connected",
        :vendor           => "redhat",
        :name             => URI.decode(vm.name),
        :location         => "#{vm.id}.ovf",
        :template         => template,
        :memory_limit     => extract_vm_memory_policy(vm, :max),
        :memory_reserve   => vm_memory_reserve(vm),
        :raw_power_state  => template ? "never" : vm.status,
        :boot_time        => vm.try(:start_time),
        :host             => persister.hosts.lazy_find(host_ems_ref),
        :ems_cluster      => persister.ems_clusters.lazy_find({:uid_ems => vm.cluster.id}, :ref => :by_uid_ems),
        :storages         => storages,
        :storage          => storages.first,
      )

      snapshots(persister_vm, vm)
      vm_hardware(persister_vm, vm, disks, template)
      operating_systems(persister_vm, vm)
      custom_attributes(persister_vm, vm)
    end
  end

  def storages(vm)
    storages = []
    disks = []
    collector.collect_attached_disks(vm).to_miq_a.each do |disk|
      next if disk.kind_of?(Array) && disk.empty?

      disks << disk
      disk.storage_domains.to_miq_a.each do |sd|
        storages << persister.storages.lazy_find(ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(sd.href))
      end
    end
    storages.compact!
    storages.uniq!

    return storages, disks
  end

  def vm_hardware(presister_vm, vm, disks, template)
    topology = vm.cpu.topology
    cpu_socks = topology.try(:sockets) || 1
    cpu_cores = topology.try(:cores) || 1

    persister_hardware = persister.hardwares.find_or_build(presister_vm).assign_attributes(
      :guest_os             => vm.dig(:os, :type),
      :annotation           => vm.try(:description),
      :cpu_cores_per_socket => cpu_cores,
      :cpu_sockets          => cpu_socks,
      :cpu_total_cores      => cpu_cores * cpu_socks,
      :memory_mb            => vm.memory / 1.megabyte
    )

    hardware_disks(persister_hardware, disks)
    addresses = hardware_networks(persister_hardware, vm) unless template
    vm_hardware_guest_devices(persister_hardware, vm, addresses) unless template
  end

  def hardware_networks(persister_hardware, vm)
    addresses = {}

    devices = collector.collect_vm_devices(vm)
    devices.to_miq_a.each do |device|
      nets = device.ips
      return addresses unless nets

      ipaddresses = ipaddresses(addresses, device, nets)
      ipaddresses.each do |ipv4address, ipv6address|
        persister.networks.find_or_build_by(
          :hardware    => persister_hardware,
          :ipaddress   => ipv4address,
          :ipv6address => ipv6address
        ).assign_attributes(
          :ipaddress   => ipv4address,
          :ipv6address => ipv6address,
          :hostname    => vm.fqdn
        )
      end
    end
    addresses
  end

  def hardware_disks(persister_hardware, disks)
    return if disks.blank?

    disks = disks.to_miq_a.sort_by do |disk|
      match = disk.try(:name).match(/disk[^\d]*(?<index>\d+)/i)
      [disk.try(:bootable) ? 0 : 1, match ? match[:index].to_i : Float::INFINITY, disk.name]
    end.group_by { |d| d.try(:interface) }

    disks.each do |interface, devices|
      devices.each_with_index do |device, index|
        storage_domain = device.storage_domains && device.storage_domains.first
        storage_ref = storage_domain && storage_domain.href

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
          :storage         => persister.storages.lazy_find(ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(storage_ref))
        )
      end
    end
  end

  def vm_hardware_guest_devices(persister_hardware, vm, addresses)
    networks = {}
    addresses.each do |mac, address|
      network = persister.networks.lazy_find_by(
        :hardware    => persister_hardware,
        :ipaddress   => address[:ipaddress],
        :ipv6address => address[:ipv6address]
      )
      networks[mac] = network if network
    end

    collector.collect_nics(vm).each do |nic|
      next if nic.blank?
      mac = nic.mac && nic.mac.address ? nic.mac.address : nil
      network = mac && networks.present? ? networks[mac] : nil

      profile_id = nic.dig(:vnic_profile, :id)
      profiles = collector.collect_vnic_profiles
      vnic_profile = profiles.detect { |p| p.id == profile_id } if profile_id && profiles
      network_id = vnic_profile.dig(:network, :id) if vnic_profile
      lan = if network_id
              switch = persister.host_virtual_switches.lazy_find(
                :host    => persister_hardware.vm_or_template&.host,
                :uid_ems => network_id
              )

              persister.lans.lazy_find(:switch => switch, :uid_ems => network_id)
            end

      persister.guest_devices.find_or_build_by(
        :hardware => persister_hardware,
        :uid_ems  => nic.id
      ).assign_attributes(
        :uid_ems         => nic.id,
        :device_name     => nic.name,
        :device_type     => 'ethernet',
        :controller_type => 'ethernet',
        :address         => nic.dig(:mac, :address),
        :lan             => lan,
        :network         => network
      )
    end
  end

  def snapshots(persister_vm, vm)
    snaps = []
    return snaps if vm.try(:snapshots).nil?

    snapshots = collector.collect_snapshots(vm)
    snapshots = snapshots.sort_by(&:date).reverse

    parent_id = nil
    snapshots.each do |snapshot|
      name = description = snapshot.description
      name = "Active Image" if name[0, 13] == '_ActiveImage_'

      snaps << persister.snapshots.find_or_build(:uid => snapshot.id).assign_attributes(
        :uid_ems        => snapshot.id,
        :uid            => snapshot.id,
        :parent_uid     => parent_id,
        :parent         => persister.snapshots.lazy_find(parent_id),
        :name           => name,
        :description    => description,
        :create_time    => snapshot.date.getutc,
        :current        => snapshot.snapshot_type == "active",
        :vm_or_template => persister_vm,
      )
      parent_id = snapshot.id
    end
    snaps
  end

  def operating_systems(persister_vm, vm)
    guest_os = vm.dig(:os, :type)

    persister.operating_systems.find_or_build(persister_vm).assign_attributes(
      :product_name => guest_os.blank? ? "Other" : guest_os,
      :system_type  => vm.type
    )
  end

  def custom_attributes(persister_vm, vm)
    custom_attrs = vm.try(:custom_properties)

    custom_attrs.to_a.each do |ca|
      persister.vm_and_template_ems_custom_fields.find_or_build(
        :resource => persister_vm,
        :name     => ca.name,
      ).assign_attributes(
        :section  => 'custom_field',
        :name     => ca.name,
        :value    => ca.value.try(:truncate, 255),
        :source   => "VC",
        :resource => persister_vm
      )
    end
  end

  private

  require 'ostruct'

  def vm_memory_reserve(vm_inv)
    extract_vm_memory_policy(vm_inv, :guaranteed)
  end

  def extract_vm_memory_policy(vm_inv, type)
    in_bytes = vm_inv.dig(:memory_policy, type)
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

  def ipaddresses(addresses, device, nets)
    ipv4addresses = []
    ipv6addresses = []
    nets.to_miq_a.each do |net|
      (net.version == "v4" ? ipv4addresses : ipv6addresses) << net.address
    end

    ipv4addresses = ipv4addresses.sort
    ipv6addresses = ipv6addresses.sort
    if device&.mac&.address
      addresses[device.mac.address] = {
        :ipaddress   => ipv4addresses.blank? ? nil : ipv4addresses.first,
        :ipv6address => ipv6addresses.blank? ? nil : ipv6addresses.first
      }
    end

    ipv4addresses.zip_stretched(ipv6addresses)
  end
end
