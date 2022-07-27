module ManageIQ::Providers
  class Ovirt::NetworkManager::Refresher < Openstack::NetworkManager::Refresher
    def collect_inventory_for_targets(ems, targets)
      targets_with_data = targets.collect do |target|
        target_name = target.try(:name) || target.try(:event_type)

        _log.info("Filtering inventory for #{target.class} [#{target_name}] id: [#{target.id}]...")

        inventory = ManageIQ::Providers::Ovirt::Inventory.build(ems, target)

        _log.info("Filtering inventory...Complete")
        [target, inventory]
      end

      targets_with_data
    end

    def parse_targeted_inventory(ems, _target, inventory)
      log_header = format_ems_for_logging(ems)
      _log.debug("#{log_header} Parsing inventory...")
      hashes, = Benchmark.realtime_block(:parse_inventory) do
        inventory.parse
      end
      _log.debug("#{log_header} Parsing inventory...Complete")

      hashes
    end
  end
end
