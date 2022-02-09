class ManageIQ::Providers::Ovirt::DialogFieldVisibilityService < ::DialogFieldVisibilityService
  attr_reader :number_of_vms_visibility_service

  def initialize(*args)
    super(*args)
    @linked_clone_visibility_service = ManageIQ::Providers::Ovirt::LinkedCloneVisibilityService.new
  end
end
