class ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager < ManageIQ::Providers::Redhat::Inventory::Parser
  def parse
    log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{collector.manager.name}] id: [#{collector.manager.id}]"
    $rhevm_log.info("#{log_header}...")

    clusters
    vmpools
    networks
    storagedomains
    datacenters
    hosts
    vms
    templates

    $rhevm_log.info("#{log_header}...Complete")
  end

  private

  def clusters
    parse_clusters(collector.clusters)
  end

  def vmpools
    parse_vmpools(collector.vmpools)
  end

  def networks
    parse_networks(collector.networks)
  end

  def storagedomains
    parse_storagedomains(collector.storagedomains)
  end

  def datacenters
    parse_datacenters(collector.datacenters)
  end

  def hosts
    parse_hosts(collector.hosts)
  end

  def vms
    parse_vms(collector.vms)
  end

  def templates
    parse_templates(collector.templates)
  end

  def parse_clusters(cluster)
    # TODO
  end

  def parse_vmpools(pools)
    # TODO
  end

  def parse_networks(networks)
    # TODO
  end

  def parse_storagedomains(domains)
    # TODO
  end

  def parse_datacenters(datacenters)
    # TODO
  end

  def parse_hosts(hosts)
    # TODO
  end

  def parse_vms(vms)
    # TODO
  end

  def parse_templates(templates)
    # TODO
  end
end
