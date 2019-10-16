class ManageIQ::Providers::Redhat::Inventory::Collector::InfraManager < ManageIQ::Providers::Redhat::Inventory::Collector
  def collected_inventory
    @collected_inventory ||= begin
                               inventory_collector = ManageIQ::Providers::Redhat::InfraManager::Inventory.new(:ems => manager)
                               inventory_collector.refresh
                             end
  end

  def ems_clusters
    collected_inventory[:cluster]
  end

  def networks
    collected_inventory[:network]
  end

  def storagedomains
    collected_inventory[:storage]
  end

  def datacenters
    collected_inventory[:datacenter]
  end

  def datacenter_by_cluster_id
    @datacenter_by_cluster_id ||= begin
      ems_clusters.each_with_object({}) do |cluster, hash|
        hash[cluster.id] = cluster.dig(:data_center, :id)
      end
    end
  end

  def hosts
    collected_inventory[:host]
  end

  def vms
    collected_inventory[:vm]
  end

  def templates
    collected_inventory[:template]
  end

  def collect_networks
    collected_inventory[:network]
  end

  def collect_vnic_profiles
    collected_inventory[:vnic_profile]
  end

  def collect_host_nics(host)
    host.nics
  end

  def collect_cluster_for_host(host)
    cluster_id = host.cluster.id
    ems_clusters.detect { |c| c.id == cluster_id }
  end

  def collect_datacenter_for_cluster(cluster)
    collected_inventory[:datacenter].detect { |dc| dc.id == cluster.data_center.id }
  end

  def collect_dc_domains(data_center)
    data_center.storage_domains
  end

  def collect_host_stats(host)
    host.statistics
  end

  def collect_attached_disks(vm)
    vm.disks
  end

  def collect_vm_devices(vm)
    vm.reported_devices
  end

  def collect_nics(vm)
    vm.nics
  end

  def collect_snapshots(vm)
    vm.snapshots
  end
end
