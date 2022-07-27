class ManageIQ::Providers::Ovirt::InfraManager::Inventory::DisksHelper
  def self.collect_attached_disks(disks_owner, connection, preloaded_disks)
    attachments = disks_owner.disk_attachments
    attachments = connection.follow_link(disks_owner.disk_attachments) if attachments.empty? && !attachments.href.nil?
    attachments.map do |attachment|
      res = disk_from_attachment(connection, attachment, preloaded_disks)
      res.interface = attachment.interface
      res.bootable = attachment.bootable
      res.active = attachment.active
      res
    end
  end

  def self.collect_disks_as_hash(connection, disks = nil)
    disks ||= connection.system_service.disks_service.list
    Hash[disks.collect { |d| [d.id, d] }]
  end

  def self.disk_from_attachment(connection, attachment, preloaded_disks)
    disk = preloaded_disks && preloaded_disks[attachment.disk.id]
    disk || connection.follow_link(attachment.disk)
  end

  private_class_method :disk_from_attachment
end
