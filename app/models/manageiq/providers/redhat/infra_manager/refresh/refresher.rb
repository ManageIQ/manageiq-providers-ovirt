module ManageIQ::Providers::Redhat::InfraManager::Refresh
  class Refresher < ManageIQ::Providers::BaseManager::Refresher
    include ::EmsRefresh::Refreshers::EmsRefresherMixin

    def collect_inventory_for_targets(ems, targets)
      inventory = inventory_from_ovirt(ems)
      raise "Invalid RHEV server ip address." if inventory.api.nil?

      # TODO: before iterating over targets it would be good to check whether ExtMgmntSystem is part of it
      # TODO optimize not to fetch the same objects like clusters for multiple targets

      targets_with_data = targets.collect do |target|
        _log.info "Filtering inventory for #{target.class} [#{target.name}] id: [#{target.id}]..."

        # TODO: make sure not to use with api v3
        if refresher_options.try(:[], :inventory_object_refresh)
          data = ManageIQ::Providers::Redhat::Builder.build_inventory(ems, target)
        else
          case target
          when Host
            data,  = Benchmark.realtime_block(:fetch_host_data) { host_targeted_refresh(inventory, target) }
          when VmOrTemplate
            data,  = Benchmark.realtime_block(:fetch_vm_data) { vm_targeted_refresh(inventory, target) }
          else
            data,  = Benchmark.realtime_block(:fetch_all) { inventory.refresh }
          end
        end

        _log.info "Filtering inventory...Complete"
        [target, data]
      end

      ems.api_version = inventory.service.version_string
      ems.save

      targets_with_data
    end

    def preprocess_targets
      # See if any should be escalated to a full refresh and do not use full_refresh_threshold
      @targets_by_ems_id.each do |ems_id, targets|
        ems = @ems_by_ems_id[ems_id]
        ems_in_list = targets.any? { |t| t.kind_of?(ExtManagementSystem) }

        if ems_in_list
          _log.info "Defaulting to full refresh for EMS: [#{ems.name}], id: [#{ems.id}]." if targets.length > 1
          targets.clear << ems
        end

        next unless refresher_options.try(:[], :inventory_object_refresh)
        all_targets, sub_ems_targets = targets.partition { |x| x.kind_of?(ExtManagementSystem) }
        unless sub_ems_targets.blank?
          ems_event_collection = ManagerRefresh::TargetCollection.new(:targets    => sub_ems_targets,
                                                                      :manager_id => ems_id)
          all_targets << ems_event_collection
        end
        @targets_by_ems_id[ems_id] = all_targets
      end
    end

    def parse_targeted_inventory(ems, _target, inventory)
      log_header = format_ems_for_logging(ems)
      _log.debug "#{log_header} Parsing inventory..."
      hashes, = Benchmark.realtime_block(:parse_inventory) do
        if refresher_options.try(:[], :inventory_object_refresh)
          inventory.inventory_collections
        else
          Parse::ParserBuilder.new(ems).build.ems_inv_to_hashes(inventory)
        end
      end
      _log.debug "#{log_header} Parsing inventory...Complete"

      hashes
    end

    def post_process_refresh_classes
      [::VmOrTemplate, ::Host]
    end

    def inventory_from_ovirt(ems)
      ems.rhevm_inventory
    end
  end
end
