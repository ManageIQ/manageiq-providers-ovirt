module ManageIQ::Providers::Redhat::InfraManager::Provision::Cloning
  def clone_complete?
    ems.ovirt_services.clone_completed?(:source        => source,
                                        :phase_context => phase_context,
                                        :logger        => _log)
  end

  def destination_image_locked?
    ems.ovirt_services.destination_image_locked?(vm)
  end

  def find_destination_in_vmdb(ems_ref)
    if source.template?
      ManageIQ::Providers::Redhat::InfraManager::Vm.find_by(:name => dest_name, :ems_ref => ems_ref)
    else
      ManageIQ::Providers::Redhat::InfraManager::Template.find_by(:name => dest_name, :ems_ref => ems_ref)
    end
  end

  def prepare_for_clone_task
    raise MiqException::MiqProvisionError, "Provision Request's Destination VM Name=[#{dest_name}] cannot be blank" if dest_name.blank?
    raise MiqException::MiqProvisionError, "A VM with name: [#{dest_name}] already exists" if source.ext_management_system.vms.where(:name => dest_name).any?

    prepare_clone_options
  end

  def prepare_clone_options
    if source.template?
      # return the options for creating a vm from the template
      vm_clone_options
    else
      # return the options for creating a template from the vm
      template_clone_options
    end
  end

  def vm_clone_options
    clone_options = {
      :name        => dest_name,
      :cluster     => dest_cluster.ems_ref,
      :clone_type  => clone_type,
      :sparse      => sparse_disk_value,
      :disk_format => disk_format
    }
    clone_options[:storage] = dest_datastore.ems_ref unless dest_datastore.nil?
    clone_options
  end

  def disk_format
    format_from_dialog = get_option(:disk_format)
    return format_from_dialog if format_from_dialog

    # If the datastore is not set, we will go with "block", because this will ensure
    # the result of the sparsity will be as set by the user.
    ds_type = 'block' unless dest_datastore
    ds_type ||= dest_datastore.store_type.to_s.downcase == 'iscsi' ? 'block' : 'file'
    # In case we want a dependant template the disk format has to be cow
    return 'cow' if clone_type == :linked
    # If it is cloned and we want the sparsity to be false the format has to be "raw"
    return 'raw' unless sparse_disk_value
    # If we need it to be sparese in case of 'file' type storage
    # we can leave the disk foramt untouched
    return nil if ds_type == 'file'
    # In case of Block storage we need to set the disk format to "cow" if we want it
    # to be sparse
    "cow"
  end

  def clone_type
    get_option(:linked_clone).nil? ? clone_type_by_disk_sparsity : clone_type_by_linked_clone
  end

  def clone_type_by_linked_clone
    get_option(:linked_clone) ? :linked : :full
  end

  def clone_type_by_disk_sparsity
    get_option(:disk_sparsity) == 'preallocated' ? :full : :linked
  end

  def template_clone_options
    clone_options = {
      :name        => dest_name,
      :cluster     => dest_cluster.ems_ref,
      :description => get_option(:vm_description),
      :seal        => get_option(:seal_template)
    }

    clone_options[:storage] = dest_datastore.ems_ref unless dest_datastore.nil?
    clone_options
  end

  def sparse_disk_value
    case get_option(:disk_sparsity)
    when "preallocated" then false
    when "thin"         then true
    when "default"      then nil   # default choice implies inherit from template
    end
  end

  def log_clone_options(clone_options)
    _log.info("Provisioning [#{source.name}] to [#{dest_name}]")
    _log.info("Source Template:            [#{source.name}]")
    _log.info("Clone Type:                 [#{clone_options[:clone_type]}]")
    _log.info("Destination VM Name:        [#{clone_options[:name]}]")
    _log.info("Destination Cluster:        [#{dest_cluster.name} (#{dest_cluster.ems_ref})]")
    _log.info("Destination Datastore:      [#{dest_datastore.name} (#{dest_datastore.ems_ref})]") unless dest_datastore.nil?
    _log.info("Seal:                       [#{clone_options[:seal]}]") unless source.template?

    dump_obj(clone_options, "#{_log.prefix} Clone Options: ", $log, :info)
    dump_obj(options, "#{_log.prefix} Prov Options:  ", $log, :info, :protected => {:path => workflow_class.encrypted_options_field_regs})
  end

  def start_clone(clone_options)
    if source.template?
      # create a vm from the template
      ems.ovirt_services.start_clone(source, clone_options, phase_context)
    else
      # create a template from the vm
      ems.ovirt_services.make_template(source, clone_options, phase_context)
    end
  end

  def ems
    ems_ref_source = (destination || source)
    return nil if ems_ref_source.nil?
    ems_ref_source.ext_management_system
  end
end
