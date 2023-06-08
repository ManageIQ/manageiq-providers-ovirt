require 'fog/openstack'
require_relative 'ovirt_refresher_spec_common'

describe ManageIQ::Providers::Ovirt::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  let(:orig_yml_path) { 'spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/ovirt_sdk_refresh_recording_for_mod.yml'.freeze }

  before(:each) do
    secrets = Rails.application.secrets.ovirt
    init_defaults(:hostname => secrets[:hostname], :ipaddress => secrets[:ipaddress])
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/ovirt/infra_manager/refresh/ovirt_sdk_refresh_recording.yml')
  end

  it "will modify the refresh recording correctly" do
    # TODO: @borod108 fix to work with network remodeling
    pending
    original_yml = YAML.load_file(orig_yml_path)
    rec_mod = RecordingModifier.new(:yml => original_yml)
    2.times { rec_mod.add_vm_with_inv }
    2.times { rec_mod.add_template_with_inv }
    2.times { rec_mod.add_host_with_inv }
    2.times { rec_mod.add_cluster_with_inv }
    vm_with_cluster_uids = rec_mod.add_vm_with_inv_and_cluster
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      opts = opts.merge(:loaded_yml => rec_mod.yml)
      Spec::Support::OvirtSDK::ConnectionVCR.new(opts, nil, false)
    end
    EmsRefresh.refresh(@ems)
    expect(@ems.vms.count).to eq(5)
    expect(@ems.hosts.count).to eq(4)
    expect(@ems.clusters.count).to eq(4)
    expect(@ems.miq_templates.count).to eq(4)
    new_vm_with_cluster = @ems.vms.where(:name => vm_with_cluster_uids[:new_vm_uid]).last
    new_cluster = @ems.clusters.where(:name => vm_with_cluster_uids[:new_cluster_uid]).last
    expect(new_vm_with_cluster.ems_cluster).to eq(new_cluster)
  end
end
