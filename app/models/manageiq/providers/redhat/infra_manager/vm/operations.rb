module ManageIQ::Providers::Redhat::InfraManager::Vm::Operations
  extend ActiveSupport::Concern

  include_concern 'Configuration'
  include_concern 'Guest'
  include_concern 'Power'
  include_concern 'Relocation'
  include_concern 'Snapshot'

  included do
    supports :terminate do
      unsupported_reason_add(:terminate, unsupported_reason(:control)) unless supports?(:control)
    end
  end

  def raw_destroy
    with_provider_object(&:destroy)
  end

  def raw_unregister
    with_provider_object(&:unregister)
  end
end
