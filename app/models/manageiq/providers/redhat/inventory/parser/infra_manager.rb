class ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager < ManageIQ::Providers::Redhat::Inventory::Parser
  # TODO: review the changes here and find common parts with ManageIQ::Providers::Redhat::InfraManager::Refresh::Parse::*
  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    $rhevm_log.info("#{log_header}...")

    clusters
    datacenters
    storagedomains
    hosts
    vms
    networks
    vnic_profiles

    $rhevm_log.info("#{log_header}...Complete")
  end

  def networks
    collector.networks.each do |network|
      is_external = id_of_external_network?(network.id)

      persister_switches = is_external ? persister.external_distributed_virtual_switches : persister.distributed_virtual_switches
      attrs_to_assign = {
        :name    => network.name,
        :uid_ems => network.id
      }

      if is_external
        datacenter = network.data_center
        ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(datacenter.href)
        parent_datacenter = persister.datacenters.lazy_find(ems_ref)

        attrs_to_assign[:parent] = parent_datacenter
      end

      persister_switches.find_or_build_by(:uid_ems => network.id)
                        .assign_attributes(attrs_to_assign)
    end
  end

  def vnic_profiles
    collector.collect_vnic_profiles.each do |vnic_profile|
      virtual_switches_persister = id_of_external_network?(vnic_profile.network.id) ? persister.external_distributed_virtual_switches : persister.distributed_virtual_switches
      virtual_lans_persister = id_of_external_network?(vnic_profile.network.id) ? persister.external_distributed_virtual_lans : persister.distributed_virtual_lans

      switch_persister = virtual_switches_persister.lazy_find(:uid_ems => vnic_profile.network.id)
      virtual_lans_persister.find_or_build_by(:uid_ems => vnic_profile.id, :switch => switch_persister).assign_attributes(
        :name    => vnic_profile.name,
        :uid_ems => vnic_profile.id
      )
    end
  end

  def id_of_external_network?(network_id)
    network = collector.networks.detect { |net| net.id == network_id }
    network&.external_provider.present?
  end

  def clusters
    collector.clusters.each do |cluster|
      r_id = "#{cluster.id}_respool"
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(cluster.href)

      persister.resource_pools.find_or_build(r_id).assign_attributes(
        :name       => "Default for Cluster #{cluster.name}",
        :uid_ems    => r_id,
        :is_default => true,
        :parent     => persister.clusters.lazy_find(ems_ref),
      )

      datacenter_id  = cluster.dig(:data_center, :id)
      cluster_parent = persister.ems_folders.lazy_find("#{datacenter_id}_host") if datacenter_id

      persister.clusters.build(
        :ems_ref     => ems_ref,
        :uid_ems     => cluster.id,
        :name        => cluster.name,
        :parent      => cluster_parent,
      )
    end
  end

  def storagedomains
    collector.storagedomains.each do |storagedomain|
      storage_type = storagedomain.dig(:storage, :type).upcase
      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(storagedomain.try(:href))
      location = case storage_type
                 when 'LOCALFS'
                   ems_ref
                 when 'NFS', 'GLUSTERFS'
                   "#{storagedomain.dig(:storage, :address)}:#{storagedomain.dig(:storage, :path)}"
                 else
                   storagedomain.dig(:storage, :volume_group, :id)
                 end

      free        = storagedomain.try(:available).to_i
      used        = storagedomain.try(:used).to_i
      total       = free + used
      committed   = storagedomain.try(:committed).to_i

      persister.storages.find_or_build(ems_ref).assign_attributes(
        :ems_ref             => ems_ref,
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
        :type    => 'ManageIQ::Providers::Redhat::InfraManager::Folder',
        :uid_ems => 'root_dc',
        :hidden  => true,
        :parent  => nil,
      )

      uid = datacenter.id
      persister.datacenters.find_or_build(ems_ref).assign_attributes(
        :name        => datacenter.name,
        :type    => 'ManageIQ::Providers::Redhat::InfraManager::Datacenter',
        :ems_ref     => ems_ref,
        :uid_ems     => uid,
        :parent      => persister.ems_folders.lazy_find("root_dc"),
      )

      host_folder_uid = "#{uid}_host"
      persister.ems_folders.find_or_build(host_folder_uid).assign_attributes(
        :name    => 'host',
        :type    => 'ManageIQ::Providers::Redhat::InfraManager::Folder',
        :uid_ems => host_folder_uid,
        :hidden  => true,
        :parent  => persister.datacenters.lazy_find(ems_ref),
      )

      vm_folder_uid = "#{uid}_vm"
      persister.ems_folders.find_or_build(vm_folder_uid).assign_attributes(
        :name    => 'vm',
        :type    => 'ManageIQ::Providers::Redhat::InfraManager::Folder',
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
        :ems_cluster      => persister.clusters.lazy_find({:uid_ems => cluster.id}, :ref => :by_uid_ems),
      )

      host_storages(dc, persister_host)
      host_operating_systems(persister_host, host, hostname)
      network_attachments = collector.collect_network_attachments(host.id)
      switches(persister_host, dc, network_attachments)
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

      persister_host_network = persister.host_networks.find_or_build_by(
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
        distributed_virtual_switch = persister.distributed_virtual_switches.lazy_find(:host => persister_host, :uid_ems => switch_uid)
        attributes[:switch] = distributed_virtual_switch
        attributes[:network] = persister_host_network
      end

      persister.host_guest_devices.find_or_build_by(
        :hardware => persister_hardware,
        :uid_ems  => nic.id
      ).assign_attributes(attributes)
    end
  end

  def switches(persister_host, _data_center, network_attachments)
    network_attachments.each do |na|
      distributed_virtual_switch = persister.distributed_virtual_switches.lazy_find(:uid_ems => na.network.id)
      persister.host_switches.find_or_build_by(
        :host   => persister_host,
        :switch => distributed_virtual_switch
      ).assign_attributes(
        :host   => persister_host,
        :switch => distributed_virtual_switch
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

  # TODO: (borod108) is this ever used?
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

    persister.distributed_virtual_lans.find_or_build_by(
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

      host_obj = vm.try(:host) || vm.try(:placement_policy).try(:hosts).try(:first)
      host_ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(host_obj.href) if host_obj.present?

      datacenter_id = collector.datacenter_by_cluster_id[vm.cluster.id]
      parent_folder = persister.ems_folders.lazy_find("#{datacenter_id}_vm")
      resource_pool = persister.resource_pools.lazy_find("#{vm.cluster.id}_respool") unless template
      host          = persister.hosts.lazy_find(host_ems_ref) if host_ems_ref.present?
      cpu_affinity  = vm.cpu&.cpu_tune&.vcpu_pins&.map { |pin| "#{pin.vcpu}##{pin.cpu_set}" }&.join(",")

      storages, disks = storages(vm)

      collection_persister = if template
                               persister.miq_templates
                             else
                               persister.vms
                             end

      attrs_to_assign = {
        :type             => template ? "ManageIQ::Providers::Redhat::InfraManager::Template" : "ManageIQ::Providers::Redhat::InfraManager::Vm",
        :ems_ref          => ems_ref,
        :uid_ems          => vm.id,
        :connection_state => "connected",
        :vendor           => "redhat",
        :name             => URI.decode(vm.name),
        :location         => "#{vm.id}.ovf",
        :template         => template,
        :memory_limit     => extract_vm_memory_policy(vm, :max),
        :memory_reserve   => vm_memory_reserve(vm),
        :raw_power_state  => template ? "never" : vm.status,
        :host             => host,
        :ems_cluster      => persister.clusters.lazy_find({:uid_ems => vm.cluster.id}, :ref => :by_uid_ems),
        :storages         => storages,
        :storage          => storages.first,
        :parent           => parent_folder,
        :resource_pool    => resource_pool,
        :cpu_affinity     => cpu_affinity
      }

      attrs_to_assign[:restart_needed] = vm.next_run_configuration_exists unless template
      attrs_to_assign[:tools_status] = get_tools_status(vm) unless template

      boot_time = vm.try(:start_time)
      attrs_to_assign[:boot_time] = boot_time unless boot_time.nil?

      persister_vm = collection_persister.find_or_build(vm.id).assign_attributes(attrs_to_assign)

      snapshots(persister_vm, vm)
      vm_hardware(persister_vm, vm, disks, template, host)
      operating_systems(persister_vm, vm)
      custom_attributes(persister_vm, vm)
    end
  end

  def get_tools_status(vm)
    apps = collector.collect_vm_guest_applications(vm).to_miq_a
    apps.any? { |app| app.name.include?('ovirt-guest-agent') } ? 'installed' : 'not installed'
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

  def vm_hardware(presister_vm, vm, disks, template, host)
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
    vm_hardware_guest_devices(persister_hardware, vm, addresses, host) unless template
  end

  def hardware_networks(persister_hardware, vm)
    addresses = {}

    devices = collector.collect_vm_devices(vm)
    devices.to_miq_a.each do |device|
      nets = device.ips
      next unless nets

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
          :thin            => device.sparse,
          :mode            => 'persistent',
          :bootable        => device.try(:bootable),
          :storage         => persister.storages.lazy_find(ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(storage_ref)),
          :format          => device.format
        )
      end
    end
  end

  def vm_hardware_guest_devices(persister_hardware, vm, addresses, host)
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

      vnic_profile_id = nic.dig(:vnic_profile, :id)
      next if vnic_profile_id.nil?

      network_uid = collector.collect_vnic_profiles.detect { |vp| vp.id == vnic_profile_id }&.network&.id
      virtual_switches_persister = id_of_external_network?(network_uid) ? persister.external_distributed_virtual_switches : persister.distributed_virtual_switches
      virtual_lans_persister = id_of_external_network?(network_uid) ? persister.external_distributed_virtual_lans : persister.distributed_virtual_lans

      switch_persister = virtual_switches_persister.lazy_find(:uid_ems => network_uid)
      lan_persister = virtual_lans_persister.lazy_find(:switch => switch_persister, :uid_ems => vnic_profile_id)

      persister.guest_devices.find_or_build_by(
        :hardware => persister_hardware,
        :uid_ems  => nic.id
      ).assign_attributes(
        :uid_ems         => nic.id,
        :device_name     => nic.name,
        :device_type     => 'ethernet',
        :controller_type => 'ethernet',
        :address         => nic.dig(:mac, :address),
        :lan             => lan_persister,
        :network         => network,
        :switch          => switch_persister
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
        :total_size     => snapshot.instance_variable_get(:@total_size)
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

    if ipaddress.nil?
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
