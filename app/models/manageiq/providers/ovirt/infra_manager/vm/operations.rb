module ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations
  extend ActiveSupport::Concern
  include Configuration
  include Guest
  include Power
  include Relocation
  include Snapshot

  included do
    supports(:terminate) { unsupported_reason(:control) }
  end

  def raw_destroy
    with_provider_object(&:destroy)
  end

  def raw_unregister
    with_provider_object(&:unregister)
  end
end
