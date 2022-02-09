class ManageIQ::Providers::Ovirt::LinkedCloneVisibilityService
  def determine_visibility(provision_type, _linked_clone, _snapshot_count)
    field_names_to_edit = []
    field_names_to_hide = []

    if provision_type.to_s == 'native_clone'
      field_names_to_edit += [:linked_clone]
    else
      field_names_to_hide += [:linked_clone]
    end

    { :hide => field_names_to_hide, :edit => field_names_to_edit }
  end
end
