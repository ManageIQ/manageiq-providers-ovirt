module ManageIQ::Providers::Redhat::InfraManager::Refresh
  class Refresher < ManageIQ::Providers::BaseManager::Refresher
    def collect_inventory_for_targets(ems, targets)
      inventory = inventory_from_ovirt(ems)
      raise "Invalid RHEV server ip address." if inventory.api.nil?

      # TODO: before iterating over targets it would be good to check whether ExtMgmntSystem is part of it
      # TODO optimize not to fetch the same objects like clusters for multiple targets

      targets_with_data = targets.collect do |target|
        _log.info "Filtering inventory for #{target.class} [#{target.name}] id: [#{target.id}]..."

        if ems.use_graph_refresh?
          data = ManageIQ::Providers::Redhat::Inventory.build(ems, target)

          # TODO: remove when graph refresh supports ems updates
          ems.api_version = inventory.service.version_string
          ems.save
        else
          case target
          when Host
            data,  = Benchmark.realtime_block(:fetch_host_data) { host_targeted_refresh(inventory, target) }
          when VmOrTemplate
            if target.template
              data,  = Benchmark.realtime_block(:fetch_template_data) { template_targeted_refresh(inventory, target) }
            else
              data,  = Benchmark.realtime_block(:fetch_vm_data) { vm_targeted_refresh(inventory, target) }
            end
          else
            data,  = Benchmark.realtime_block(:fetch_all) { inventory.refresh }
          end
        end

        empty_hash_when_target_not_found!(target, data) if targeted_refresh?(target)

        case ems.highest_allowed_api_version
        when '3'
          data[:ems_api_version] = {:api_version => inventory.service.version_string}
        when '4'
          data.instance_variable_set(:@ems_api_version, :api_version => inventory.service.version_string)
        end

        _log.info "Filtering inventory...Complete"
        [target, data]
      end

      ems.ensure_managers

      targets_with_data
    end

    def preprocess_targets
      @targets_by_ems_id.each do |ems_id, targets|
        ems = @ems_by_ems_id[ems_id]
        ems_in_list = targets.any? { |t| t.kind_of?(ExtManagementSystem) }

        if ems_in_list
          _log.info "Defaulting to full refresh for EMS: [#{ems.name}], id: [#{ems.id}]." if targets.length > 1
          targets.clear << ems
        end

        next unless ems.use_graph_refresh?
        all_targets, sub_ems_targets = targets.partition { |x| x.kind_of?(ExtManagementSystem) }
        unless sub_ems_targets.blank?
          ems_event_collection = InventoryRefresh::TargetCollection.new(:targets    => sub_ems_targets,
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
        if ems.use_graph_refresh?
          inventory.parse
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

    private

    def empty_hash_when_target_not_found!(target, data)
      empty_the_hash!(data) if corresponding_hashes_empty?(target, data)
    end

    def targeted_refresh?(target)
      target.kind_of?(VmOrTemplate) || target.kind_of?(Host)
    end

    def empty_the_hash!(data)
      data.each_key { |k| data[k] = nil }
    end

    def corresponding_hashes_empty?(target, data)
      case target
      when VmOrTemplate
        return data[:template].blank? if target.template?
        data[:vm].blank?
      when Host
        data[:host].blank?
      else
        false
      end
    end
  end
end
