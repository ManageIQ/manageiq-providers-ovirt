module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::VmsCollections
  extend ActiveSupport::Concern

  # group :vms
  def add_miq_templates
    add_collection(infra, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Redhat::InfraManager::Template)

      builder.add_properties(:manager_uuids => references(:vms)) if targeted?
    end
  end

  # group :vms
  def add_vm_and_template_ems_custom_fields
    add_collection(infra, :vm_and_template_ems_custom_fields, {}, {:auto_inventory_attributes => false}) do |builder|
      builder.add_properties(
        :model_class                  => ::CustomAttribute,
        :manager_ref                  => %i(name),
        :parent_inventory_collections => %i(vms)
      )

      builder.add_inventory_attributes(%i(section name value source resource))
    end
  end
end
