require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  let(:counted_models) { [CustomAttribute, EmsFolder, EmsCluster, Datacenter].freeze }

  before(:each) do
    init_defaults
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/ovirt_sdk_refresh_graph_target_template.yml')
  end

  it 'refreshes template host properly when placement_policy defined' do
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts,
                                                 'spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/ovirt_sdk_refresh_graph_target_template_with_host.yml',
                                                 false)
    end
    EmsRefresh.refresh(@ems)
    @ems.reload
    template = VmOrTemplate.where(:name => "template_cd2").first
    expect(template.ems_id).to eq(@ems.id)
    expect(template.host_id).to be_present
    saved_template       = template_to_comparable_hash(template)
    saved_counted_models = counted_models.map { |m| [m.name, m.count] }
    template.host        = nil
    template.save
    EmsRefresh.refresh(template)
    template.reload
    all_counted_models = counted_models.map { |m| [m.name, m.count] }
    expect(saved_template).to eq(template_to_comparable_hash(template))
    expect(saved_counted_models).to eq(all_counted_models)
  end

  it 'does not change the template when target refresh after full refresh' do
    EmsRefresh.refresh(@ems)
    @ems.reload
    template = VmOrTemplate.where(:name => "template_cd1").first
    expect(template.ems_id).to eq(@ems.id)
    saved_template = template_to_comparable_hash(template)
    ENV["deb"]     = "true"
    EmsRefresh.refresh(template)
    template.reload
    expect(saved_template).to eq(template_to_comparable_hash(template))
  end

  def template_to_comparable_hash(template)
    h = template.attributes
    h.delete("updated_on")
    h.delete("state_changed_on")
    h
  end
end
