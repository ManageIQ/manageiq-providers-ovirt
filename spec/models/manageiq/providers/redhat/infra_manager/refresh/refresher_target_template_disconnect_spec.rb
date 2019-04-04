require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_target_template_disconnect.yml')

    stub_settings_merge(:ems => {:ems_redhat => {:use_ovirt_engine_sdk => true}})
    stub_settings_merge(:ems_refresh => {:rhevm => {:inventory_object_refresh => false}})
  end

  it 'removes connection of ems if template is deleted on provider' do
    EmsRefresh.refresh(@ems)
    @ems.reload
    template = VmOrTemplate.where(:name => "ubu_pab10").first
    # At this point the template was deleted from the provider
    expect(template.ems_id).to eq(@ems.id)
    EmsRefresh.refresh(template)
    expect(template.reload.ems_id).to be_nil
  end
end
