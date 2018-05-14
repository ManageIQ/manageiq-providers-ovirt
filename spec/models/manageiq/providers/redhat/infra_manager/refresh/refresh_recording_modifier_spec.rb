require 'fog/openstack'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  before(:each) do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryGirl.create(:ems_redhat, :zone => zone, :hostname => "pluto-vdsg.eng.lab.tlv.redhat.com", :ipaddress => "10.35.19.13",
                              :port => 443)
    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "123456"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
    allow(@ems).to(receive(:supported_api_versions).and_return(%w(3 4)))
    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original

    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  before(:each) do
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4

    allow_any_instance_of(@inventory_wrapper_class).to(receive(:api).and_return("4.2.0_master."))
    allow_any_instance_of(@inventory_wrapper_class).to(receive(:service)
      .and_return(OpenStruct.new(:version_string => '4.2.0_master.')))
  end

  require 'yaml'
  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
  end

  ORIG_YML_PATH = 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording_for_mod.yml'.freeze

  it "will modify the refresh recording correctly" do
    original_yml = YAML.load_file(ORIG_YML_PATH)
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
