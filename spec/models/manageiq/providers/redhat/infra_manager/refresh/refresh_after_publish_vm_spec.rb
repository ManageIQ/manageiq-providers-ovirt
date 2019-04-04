require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_publish_vm_to_template.yml')

    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => false }})
  end

  it 'removes connection of ems if template is deleted on provider' do
    EmsRefresh.refresh(@ems)
    @ems.reload
    vm = VmOrTemplate.find_by(:name => "ubu_met")
    template_after_publish_target_hash = load_response_mock_for("template_after_publish_target_hash")
    target_klass = "ManageIQ::Providers::Redhat::InfraManager::Template"
    target_find = { :uid_ems => "7d97cc6a-5c96-40f7-950b-a89c316cc377" }
    expect(vm.ems_cluster).not_to be_nil
    EmsRefresh.refresh_new_target(@ems.id, template_after_publish_target_hash, target_klass, target_find)
    expect(vm.ems_cluster).not_to be_nil
  end
end
