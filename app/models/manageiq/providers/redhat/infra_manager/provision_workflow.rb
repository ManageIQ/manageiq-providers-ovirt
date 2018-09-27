class ManageIQ::Providers::Redhat::InfraManager::ProvisionWorkflow < MiqProvisionInfraWorkflow
  include CloudInitTemplateMixin
  include SysprepTemplateMixin

  SYSPREP_TIMEZONES = {
    '001' => '(UTC-12:00) Dateline Standard Time',
    '002' => '(UTC-11:00) UTC-11',
    '003' => '(UTC-10:00) Hawaiian Standard Time',
    '004' => '(UTC-09:00) Alaskan Standard Time',
    '005' => '(UTC-08:00) Pacific Standard Time',
    '006' => '(UTC-07:00) US Mountain Standard Time',
    '007' => '(UTC-07:00) Mountain Standard Time',
    '008' => '(UTC-06:00) Central America Standard Time',
    '009' => '(UTC-06:00) Central Standard Time',
    '010' => '(UTC-06:00) Canada Central Standard Time',
    '011' => '(UTC-05:00) SA Pacific Standard Time',
    '012' => '(UTC-05:00) Eastern Standard Time',
    '013' => '(UTC-05:00) US Eastern Standard Time',
    '014' => '(UTC-04:30) Venezuela Standard Time',
    '015' => '(UTC-04:00) Paraguay Standard Time',
    '016' => '(UTC-04:00) Atlantic Standard Time',
    '017' => '(UTC-04:00) Central Brazilian Standard Time',
    '018' => '(UTC-04:00) SA Western Standard Time',
    '019' => '(UTC-04:00) Pacific SA Standard Time',
    '020' => '(UTC-03:30) Newfoundland Standard Time',
    '021' => '(UTC-03:00) E. South America Standard Time',
    '022' => '(UTC-03:00) Argentina Standard Time',
    '023' => '(UTC-03:00) SA Eastern Standard Time',
    '024' => '(UTC-03:00) Greenland Standard Time',
    '025' => '(UTC-03:00) Montevideo Standard Time',
    '026' => '(UTC-03:00) Bahia Standard Time',
    '027' => '(UTC-02:00) UTC-02',
    '028' => '(UTC-01:00) Azores Standard Time',
    '029' => '(UTC-01:00) Cape Verde Standard Time',
    '030' => '(UTC) Morocco Standard Time',
    '031' => '(UTC) UTC',
    '032' => '(UTC) GMT Standard Time',
    '033' => '(UTC) Greenwich Standard Time',
    '034' => '(UTC+01:00) W. Europe Standard Time',
    '035' => '(UTC+01:00) Central Europe Standard Time',
    '036' => '(UTC+01:00) Romance Standard Time',
    '037' => '(UTC+01:00) Central European Standard Time',
    '038' => '(UTC+01:00) Libya Standard Time',
    '039' => '(UTC+01:00) W. Central Africa Standard Time',
    '040' => '(UTC+01:00) Namibia Standard Time',
    '041' => '(UTC+02:00) GTB Standard Time',
    '042' => '(UTC+02:00) Middle East Standard Time',
    '043' => '(UTC+02:00) Egypt Standard Time',
    '044' => '(UTC+02:00) Syria Standard Time',
    '045' => '(UTC+02:00) E. Europe Standard Time',
    '046' => '(UTC+02:00) South Africa Standard Time',
    '047' => '(UTC+02:00) FLE Standard Time',
    '048' => '(UTC+02:00) Turkey Standard Time',
    '049' => '(UTC+02:00) Israel Standard Time',
    '050' => '(UTC+03:00) Jordan Standard Time',
    '051' => '(UTC+03:00) Arabic Standard Time',
    '052' => '(UTC+03:00) Kaliningrad Standard Time',
    '053' => '(UTC+03:00) Arab Standard Time',
    '054' => '(UTC+03:00) E. Africa Standard Time',
    '055' => '(UTC+03:30) Iran Standard Time',
    '056' => '(UTC+04:00) Arabian Standard Time',
    '057' => '(UTC+04:00) Azerbaijan Standard Time',
    '058' => '(UTC+04:00) Russian Standard Time',
    '059' => '(UTC+04:00) Mauritius Standard Time',
    '060' => '(UTC+04:00) Georgian Standard Time',
    '061' => '(UTC+04:00) Caucasus Standard Time',
    '062' => '(UTC+04:30) Afghanistan Standard Time',
    '063' => '(UTC+05:00) West Asia Standard Time',
    '064' => '(UTC+05:00) Pakistan Standard Time',
    '065' => '(UTC+05:30) India Standard Time',
    '066' => '(UTC+05:30) Sri Lanka Standard Time',
    '067' => '(UTC+05:45) Nepal Standard Time',
    '068' => '(UTC+06:00) Central Asia Standard Time',
    '069' => '(UTC+06:00) Bangladesh Standard Time',
    '070' => '(UTC+06:00) Ekaterinburg Standard Time',
    '071' => '(UTC+06:30) Myanmar Standard Time',
    '072' => '(UTC+07:00) SE Asia Standard Time',
    '073' => '(UTC+07:00) N. Central Asia Standard Time',
    '074' => '(UTC+08:00) China Standard Time',
    '075' => '(UTC+08:00) North Asia Standard Time',
    '076' => '(UTC+08:00) Singapore Standard Time',
    '077' => '(UTC+08:00) W. Australia Standard Time',
    '078' => '(UTC+08:00) Taipei Standard Time',
    '079' => '(UTC+08:00) Ulaanbaatar Standard Time',
    '080' => '(UTC+09:00) North Asia East Standard Time',
    '081' => '(UTC+09:00) Tokyo Standard Time',
    '082' => '(UTC+09:00) Korea Standard Time',
    '083' => '(UTC+09:30) Cen. Australia Standard Time',
    '084' => '(UTC+09:30) AUS Central Standard Time',
    '085' => '(UTC+10:00) E. Australia Standard Time',
    '086' => '(UTC+10:00) AUS Eastern Standard Time',
    '087' => '(UTC+10:00) West Pacific Standard Time',
    '088' => '(UTC+10:00) Tasmania Standard Time',
    '089' => '(UTC+10:00) Yakutsk Standard Time',
    '090' => '(UTC+11:00) Central Pacific Standard Time',
    '091' => '(UTC+11:00) Vladivostok Standard Time',
    '092' => '(UTC+12:00) New Zealand Standard Time',
    '093' => '(UTC+12:00) UTC+12',
    '094' => '(UTC+12:00) Fiji Standard Time',
    '095' => '(UTC+12:00) Magadan Standard Time',
    '096' => '(UTC+13:00) Tonga Standard Time',
    '097' => '(UTC+13:00) Samoa Standard Time'
  }.freeze

  def get_timezones(_options = {})
    SYSPREP_TIMEZONES
  end

  def self.default_dialog_file
    'miq_provision_dialogs'
  end

  def self.provider_model
    ManageIQ::Providers::Redhat::InfraManager
  end

  def supports_pxe?
    get_value(@values[:provision_type]).to_s == 'pxe'
  end

  def supports_iso?
    get_value(@values[:provision_type]).to_s == 'iso'
  end

  def supports_native_clone?
    get_value(@values[:provision_type]).to_s == 'native_clone'
  end

  def supports_linked_clone?
    supports_native_clone? && get_value(@values[:linked_clone])
  end

  def supports_cloud_init?
    true
  end

  def allowed_provision_types(_options = {})
    {
      "pxe"          => "PXE",
      "iso"          => "ISO",
      "native_clone" => "Native Clone"
    }
  end

  def dialog_name_from_automate(message = 'get_dialog_name')
    super(message, {'platform' => 'redhat'})
  end

  def update_field_visibility
    super(:force_platform => 'linux')
  end

  def update_field_visibility_linked_clone(_options = {}, f)
    show_flag = supports_native_clone? ? :edit : :hide
    f[show_flag] << :linked_clone

    show_flag = supports_linked_clone? ? :hide : :edit
    f[show_flag] << :disk_format
  end

  def allowed_customization_templates(options = {})
    if supports_native_clone?
      if get_source_vm&.platform == 'windows'
        allowed_sysprep_customization_templates(options)
      else
        allowed_cloud_init_customization_templates(options)
      end
    else
      super(options)
    end
  end

  def allowed_datacenters(_options = {})
    super.slice(datacenter_by_vm.try(:id))
  end

  def allowed_customization(_options = {})
    src = get_source_and_targets
    return {} if src.blank?
    return {"fields" => "Specification"} if @values[:forced_sysprep_enabled] == 'fields'

    result = {"disabled" => "<None>"}

    case src[:vm].platform
    when 'windows'
      result["file"] = "Sysprep Answer File"
      result["fields"] = "Sysprep Specification"
    when 'linux'
      result["fields"] = "Specification"
    end

    result
  end

  def datacenter_by_vm
    @datacenter_by_vm ||= begin
                            vm = resources_for_ui[:vm]
                            VmOrTemplate.find(vm.id).parent_datacenter if vm
                          end
  end

  def set_on_vm_id_changed
    @datacenter_by_vm = nil
    super
  end

  def allowed_hosts_obj(_options = {})
    super(:datacenter => datacenter_by_vm)
  end

  def allowed_storages(options = {})
    return [] if (src = resources_for_ui).blank?
    result = super

    if supports_linked_clone?
      s_id = load_ar_obj(src[:vm]).storage_id
      result = result.select { |s| s.id == s_id }
    end

    result.select { |s| s.storage_domain_type == "data" }
  end

  def source_ems
    src = get_source_and_targets
    load_ar_obj(src[:ems])
  end

  def load_allowed_vlans(hosts, vlans)
    ems = source_ems
    ems.ovirt_services.load_allowed_networks(hosts, vlans, self) if ems
  end

  def ws_network_fields(values, fields, data)
    requested_vlan = data[:vlan]
    super(values, fields, data)
    return if (dlg_fields = get_ws_dialog_fields(:network)).nil?
    if values[:vlan].nil?
      dlg_fields_vlan = dlg_fields[:vlan]
      field_values = dlg_fields_vlan && dlg_fields_vlan[:values]
      values[:vlan] = field_values&.values&.detect { |value| value == requested_vlan }
    end
  end

  def filter_allowed_hosts(all_hosts)
    ems = source_ems
    return all_hosts unless ems
    ovirt_services = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Builder.new(ems).build(:use_highest_supported_version => true).new(:ems => ems)
    ovirt_services.filter_allowed_hosts(self, all_hosts)
  end

  def set_or_default_hardware_field_values(vm)
    unless source_ems.use_ovirt_sdk?
      vm.memory_limit = nil
    end
    super(vm)
  end

  def validate_memory_limit(_field, values, dlg, fld, _value)
    limited = get_value(values[:memory_limit])
    return nil if limited.nil? || limited.zero?

    ems = source_ems
    return nil if ems.blank?
    unless ems.use_ovirt_sdk?
      return _("Memory Limit is supported only when using ovirt-engine-sdk (To enable, set: ':use_ovirt_engine_sdk: true' in settings.yml).")
    end

    unless ems.version_at_least?("4.1")
      return _("Memory Limit is supported for RHV 4.1 and above. Current provider version is #{ems.api_version}.")
    end

    allocated = get_value(values[:vm_memory]).to_i
    if allocated > limited.to_i
      _("%{description} VM Memory is larger than Memory Limit") % {:description => required_description(dlg, fld)}
    end
  end

  def validate_seal_template(_field, values, _dlg, _fld, _value)
    seal = get_value(values[:seal_template])
    return nil unless seal

    if get_source_vm.platform == 'windows'
      _("Template sealing is supported only for non-Windows OS.")
    end
  end
end
