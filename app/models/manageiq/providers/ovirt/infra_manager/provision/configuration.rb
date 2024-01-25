module ManageIQ::Providers::Ovirt::InfraManager::Provision::Configuration
  extend ActiveSupport::Concern

  include Container
  include Network

  def attach_floppy_payload
    return unless content = customization_template_content
    filename = customization_template.default_filename
    with_provider_destination { |d| d.attach_floppy(filename => content) }
  end

  def configure_cloud_init
    return unless content = customization_template_content
    with_provider_destination { |d| d.update_cloud_init!(content) }

    ems_api_version = source.ext_management_system.api_version
    if ems_api_version && Gem::Version.new(ems_api_version) >= Gem::Version.new("3.5.5.0")
      phase_context[:boot_with_cloud_init] = true
    end
  end

  def configure_sysprep
    content = sysprep_specification_selected? ? customization_template_content : get_option(:sysprep_upload_text)
    return unless content
    with_provider_destination { |d| d.update_sysprep!(content) }

    phase_context[:boot_with_sysprep] = true
  end

  def configure_container
    vm.with_provider_object do |rhevm_vm|
      configure_container_description(rhevm_vm)
      configure_memory(rhevm_vm)
      configure_memory_reserve(rhevm_vm)
      configure_cpu(rhevm_vm)
      configure_host_affinity(rhevm_vm)
      configure_network_adapters
      sysprep_option = get_option(:sysprep_enabled)
      if sysprep_option == 'file' || sysprep_specification_selected?
        configure_sysprep
      elsif sysprep_option == 'fields'
        configure_cloud_init
      end
    end
  end

  private

  def sysprep_specification_selected?
    options.dig(:sysprep_enabled, 1) == "Sysprep Specification"
  end

  def prepare_customization_template_substitution_options(mac_address = nil)
    super.tap do |substitution_options|
      substitution_options[:sysprep_timezone] = extract_timezone(substitution_options[:sysprep_timezone]) if substitution_options
    end
  end

  def extract_timezone(timezone_option_from_ui)
    timezone = timezone_option_from_ui[1] if timezone_option_from_ui.present?
    return unless timezone
    /\) (.*)/.match(timezone)[1]
  end

  def customization_template_content
    return unless customization_template
    options = prepare_customization_template_substitution_options
    customization_template.script_with_substitution(options)
  end
end
