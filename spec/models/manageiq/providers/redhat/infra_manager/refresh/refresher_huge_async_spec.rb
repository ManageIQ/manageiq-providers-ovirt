#### This file is meant to be run on local to simulate scale environment,
#### Please follow the comments on how to do it.

require 'fog/openstack'

describe ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher do
  before(:each) do
    _guid, _server, @zone = EvmSpecHelper.create_guid_miq_server_zone
    create_ems
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original
    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  def create_ems
    @ems = FactoryBot.create(:ems_redhat, :zone => @zone, :hostname => "pluto-vdsg.eng.lab.tlv.redhat.com", :ipaddress => "10.35.19.13",
                              :port => 443)
    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::Strategies::V4
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for('external_network_providers'))
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "123456"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
    allow(@ems).to(receive(:supported_api_versions).and_return(%w(3 4)))
  end

  before(:each) do
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory::Strategies::V4

    allow_any_instance_of(@inventory_wrapper_class).to(receive(:api).and_return("4.2.0_master."))
    allow_any_instance_of(@inventory_wrapper_class).to(receive(:service)
      .and_return(OpenStruct.new(:version_string => '4.2.0_master.')))
  end

  require 'yaml'

  ORIG_YML_PATH = 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording_for_mod.yml'.freeze

  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
  end

  it "will perform a full refresh on v4.1" do
    original_yml = YAML.load_file(ORIG_YML_PATH)
    rec_mod = RecordingModifier.new(:yml => original_yml)

    2.times do
      cl_uid = rec_mod.add_cluster_with_inv
      3.times do
        rec_mod.add_vm_to_cluster(cl_uid)
      end
      1.times do
        rec_mod.add_host_to_cluster(cl_uid)
      end
    end
    1.times { rec_mod.add_template_with_inv }

    # To simulate scale env uncomment the next few lines that generate a huge env, note it takes a long time to generate
    # so write it to file and use the file if we want to run it several times:

    # 3.times do
      # cl_uid = rec_mod.add_cluster_with_inv
      # 1300.times do
        # rec_mod.add_vm_to_cluster(cl_uid)
      # end
      # 120.times do
        # rec_mod.add_host_to_cluster(cl_uid)
      # end
    # end
    # 14.times { rec_mod.add_template_with_inv }

    # File.write('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/tmp1.yml', rec_mod.yml.to_yaml)
    # @rec_yml = YAML.load_file('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/tmp1.yml')

    @rec_yml ||= rec_mod.yml
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
      @opts = opts.merge(:loaded_yml => Marshal.load(Marshal.dump(@rec_yml)))
      @vcr = Spec::Support::OvirtSDK::ConnectionVCR.new(@opts, nil, false)
      @vcr
    end

    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => true }})

    with_graph_results = []
    1.times do |n|
      res = refresh_once(@rec_yml, n)
      with_graph_results << res[1][:save_inventory]
      cleanup
    end

    stub_settings_merge(:ems_refresh => { :rhevm => {:inventory_object_refresh => false }})

    without_graph_results = []
    1.times do |n|
      res = refresh_once(@rec_yml, n + 10)
      without_graph_results << res[1][:save_inventory]
      cleanup
    end

    # uncomment the following lines to get printouts of the timing for the save_inventory
    # expect(res_old_refresh[:ems_refresh]).to be > res_graph_refresh[:ems_refresh]
    # puts "with graph refresh results: #{with_graph_results}"
    # puts "variance: #{variance(with_graph_results)}"
    # puts "mean: #{mean(with_graph_results)}"
    # puts "without graph refresh results: #{without_graph_results}"
    # puts "variance: #{variance(without_graph_results)}"
    # puts "mean: #{mean(without_graph_results)}"
  end

  # To get profiling, gem install ruby-prof
  # then uncomment the lines ending with #ruby-prof
  # require 'ruby-prof' #ruby-prof
  def refresh_once(rec_yml, n = 0)
    # result = nil #ruby-prof
    res_graph_refresh = Benchmark.realtime_block(:refresh_huge) do
      # RubyProf.start #ruby-prof
      EmsRefresh.refresh(@ems)
      # result = RubyProf.stop #ruby-prof
    end
    # printer = RubyProf::MultiPrinter.new(result) #ruby-prof
    # system 'mkdir', "result#{n}" #ruby-prof
    # printer.print(:path => "./result#{n}", :profile => "profile") #ruby-prof
    @vcr.load_new_cassete(:loaded_yml => Marshal.load(Marshal.dump(rec_yml)))
    res_graph_refresh
  end

  def cleanup
    [VmOrTemplate, ExtManagementSystem, Host, EmsCluster, EmsFolder, HostSwitch, HostStorage, Snapshot, ResourcePool, Relationship,
     OperatingSystem, Network, Hardware, Lan, GuestDevice, Disk, Storage, Switch].each(&:delete_all)
    create_ems
  end

  def mean(list)
    list.reduce(:+) / list.length.to_r
  end

  def variance(list)
    sum_of_squared_differences = list.map { |i| (i - mean(list))**2 }.reduce(:+)
    sum_of_squared_differences / list.length
  end
end
