module ManageIQ::Providers::Redhat::Inventory::Persister::Definitions::InfraGroup::VmsCollections
  extend ActiveSupport::Concern

  # group :vms
  def add_miq_templates
    add_collection(infra, :miq_templates) do |builder|
      builder.add_properties(:model_class => ::ManageIQ::Providers::Redhat::InfraManager::Template)

      builder.add_properties(:manager_uuids => references(:vms)) if targeted?
    end
  end

  def add_snapshots
    add_collection(infra, :snapshots) do |builder|
      builder.add_properties(
        :manager_ref => %i(uid),
        :strategy    => :local_db_find_missing_references,
      )
    end
  end
end
