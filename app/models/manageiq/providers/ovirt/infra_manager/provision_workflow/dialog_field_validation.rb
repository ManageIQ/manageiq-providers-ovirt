module ManageIQ::Providers::Ovirt::InfraManager::ProvisionWorkflow::DialogFieldValidation
  def validate_disks_configuration(_field, _values, _dlg, _fld, _value)
    sparsity = get_value(@values[:disk_sparsity])
    format = get_value(@values[:disk_format])
    linked_clone = get_value(@values[:linked_clone])
    vm_id = get_value(@values[:src_vm_id])
    vm = VmOrTemplate.find(vm_id)

    if linked_clone
      if !(default?(sparsity) && default?(format)) || storage_changed_for_disks?(vm)
        return _("When the 'Linked Clone' option is set, disks and storage configuration cannot be changed")
      end
    end
    disks = vm.disks
    disks.each do |disk|
      unless validate_disk(disk)
        return _("The requested disk configuration for disk #{disk.device_name} is #{requested_disk_sparsity(disk)} with #{requested_disk_format(disk)} format.
                 This configuration cannot be provisioned on the requested storage")
      end
    end
    nil
  end

  def requested_disk_format(disk)
    format = get_value(@values[:disk_format])
    default?(format) ? disk.format : format
  end

  def requested_disk_sparsity(disk)
    sparsity = get_value(@values[:disk_sparsity])
    disk_sparsity = default?(sparsity) ? disk.thin : sparsity
    case disk_sparsity
    when true, "sparse"
      "sparse"
    else
      "preallocated"
    end
  end

  def storage_type_from_storage(storage)
    storage.store_type.to_s.downcase == 'iscsi' ? 'block' : 'file'
  end

  def storage_type
    return nil unless dest_storage&.store_type

    storage_type_from_storage(dest_storage)
  end

  DISK_CONFIGURATIONS = {
    "file,raw,preallocated"  => true,
    "file,raw,sparse"        => true,
    "file,cow,sparse"        => true,
    "block,raw,preallocated" => true,
    "block,cow,sparse"       => true
  }.freeze

  def validate_disk(disk, opts = {})
    disk_format = requested_disk_format(disk)
    disk_sparsity = requested_disk_sparsity(disk)
    validate_disk_configuration(opts[:storage_type] || storage_type, disk_format, disk_sparsity)
  end

  def validate_disk_configuration(storage_type, format, sparsity)
    # is storage_type is not given we will assume it is "file" this way it will not block the validation,
    # in reality the allowed_storages will actually run over each of the configurations with the available storages
    # and will block the provisioning process if none of them is valid.
    str_type = storage_type || "file"
    DISK_CONFIGURATIONS["#{str_type},#{format},#{sparsity}"]
  end

  def dest_storage
    ds_id = get_value(@values[:placement_ds_name])
    Storage.find(ds_id)
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def storage_changed_for_disks?(vm)
    return false unless dest_storage

    vm.disks.inject(false) { |res, disk| res || disk.storage_id != dest_storage.id }
  end

  def default?(str)
    str == "default" || str.nil?
  end
end
