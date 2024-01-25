module ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations
  extend ActiveSupport::Concern
  include Configuration
  include Guest
  include Power
  include Relocation
  include Snapshot

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
