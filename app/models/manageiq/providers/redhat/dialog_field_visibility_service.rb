class ManageIQ::Providers::Redhat::DialogFieldVisibilityService < ::DialogFieldVisibilityService
  attr_reader :number_of_vms_visibility_service

  def initialize(*args)
    super(*args)
    @linked_clone_visibility_service = ManageIQ::Providers::Redhat::LinkedCloneVisibilityService.new
  end
end
