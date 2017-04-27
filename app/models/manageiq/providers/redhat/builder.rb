class ManageIQ::Providers::Redhat::Builder
  class << self
    def build_inventory(ems, target)
      if target.kind_of? ManagerRefresh::TargetCollection
        inventory(
          ems,
          target,
          ManageIQ::Providers::Redhat::Inventory::Collector::TargetCollection,
          ManageIQ::Providers::Redhat::Inventory::Persister::TargetCollection,
          [parser]
        )
      else
        # Fallback to ems refresh or full refresh
        infra_manager_inventory(ems, target)
      end
    end

    private

    def parser
      ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager
    end

    def infra_manager_inventory(ems, target)
      inventory(
        ems,
        target,
        ManageIQ::Providers::Redhat::Inventory::Collector::InfraManager,
        ManageIQ::Providers::Redhat::Inventory::Persister::InfraManager,
        [parser]
      )
    end

    def inventory(manager, raw_target, collector_class, persister_class, parsers_classes)
      collector = collector_class.new(manager, raw_target)
      persister = persister_class.new(manager, raw_target, collector)

      ::ManageIQ::Providers::Redhat::Inventory.new(
        persister,
        collector,
        parsers_classes.map(&:new)
      )
    end
  end
end
