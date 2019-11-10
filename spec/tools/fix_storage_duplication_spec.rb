require 'fog/openstack'
require_relative '../models/manageiq/providers/redhat/infra_manager/refresher/ovirt_refresher_spec_common'

$LOAD_PATH << Rails.root.join("tools").to_s
require "handle_rhv_storage_duplication"

describe ManageIQ::Providers::Redhat::InfraManager::Refresher do
  include OvirtRefresherSpecCommon

  before(:each) do
    init_defaults(:hostname => 'pluto-vdsg.eng.lab.tlv.redhat.com', :ipaddress => '10.35.19.13', :port => 443)
    init_connection_vcr('spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/fix_storage_duplication_recording.yml')
    stub_const("ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager", ManageIQ::Providers::Redhat::Inventory::Parser::MockedInfraManager)
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
  end

  it "duplicates are properly merged" do
    EmsRefresh.refresh(@ems)
    VCR.use_cassette("#{described_class.parent.name.underscore}/refresh/refresher_ovn_provider") do
      Fog::OpenStack.instance_variable_set(:@version, nil)
      EmsRefresh.refresh(@ems.network_manager)
    end
    @ems.reload

    storages = @ems.storages
    expect(storages.count).to eq(3)
    expect(Storage.all.count).to eq(7)
    storage1 = Storage.where(:location => "3600a09803830355a332b47677750716c").first
    storage2 = Storage.where(:location => "36001405ee0b74100598487e9c5f90850").first
    storage1.tag_with("red blue yellow", :ns => "/test", :cat => "tags")
    storage2.tag_with("Red Blue Yellow", :ns => "/Test", :cat => "MixedCase")

    storage1_tags = storage1.tags.collect(&:name)
    storage2_tags = storage2.tags.collect(&:name)

    stub_const("ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager", ManageIQ::Providers::Redhat::Inventory::Parser::OriginInfraManager)
    EmsRefresh.refresh(@ems)
    expect(Storage.all.count).to eq(9)

    hsd = HandleStorageDuplication.new({})
    hsd.handle_duplicates
    expect(Storage.all.count).to eq(7)
    expect(storages.reload.count).to eq(3)

    storage1_new = Storage.where(:location => "pkQKmN-YRZS-X90X-nCed-nm1A-b3yH-b1t8tm").first
    storage2_new = Storage.where(:location => "Zpmh5m-WxsN-Ws3S-2nVy-tI4y-EZlt-EcMwzE").first

    storage1_new_tags = storage1_new.tags.collect(&:name)
    storage2_new_tags = storage2_new.tags.collect(&:name)

    expect(storage1_new_tags).to match_array(storage1_tags)
    expect(storage2_new_tags).to match_array(storage2_tags)
  end
end

class ManageIQ::Providers::Redhat::Inventory::Parser::OriginInfraManager < ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager
end

class ManageIQ::Providers::Redhat::Inventory::Parser::MockedInfraManager < ManageIQ::Providers::Redhat::Inventory::Parser::InfraManager
  def storagedomains
    collector.storagedomains.each do |storagedomain|
      storage_type = storagedomain.dig(:storage, :type).upcase
      location = if storage_type == 'NFS' || storage_type == 'GLUSTERFS'
                   "#{storagedomain.dig(:storage, :address)}:#{storagedomain.dig(:storage, :path)}"
                 else
                   logical_units = storagedomain.dig(:storage, :volume_group, :logical_units)
                   logical_unit =  logical_units && logical_units.first
                   logical_unit && logical_unit.id
                 end

      free        = storagedomain.try(:available).to_i
      used        = storagedomain.try(:used).to_i
      total       = free + used
      committed   = storagedomain.try(:committed).to_i

      ems_ref = ManageIQ::Providers::Redhat::InfraManager.make_ems_ref(storagedomain.try(:href))

      persister.storages.find_or_build(ems_ref).assign_attributes(
        :ems_ref             => ems_ref,
        :ems_ref_obj         => ems_ref,
        :name                => storagedomain.try(:name),
        :store_type          => storage_type,
        :storage_domain_type => storagedomain.dig(:type, :downcase),
        :total_space         => total,
        :free_space          => free,
        :uncommitted         => total - committed,
        :multiplehostaccess  => true,
        :location            => location,
        :master              => storagedomain.try(:master)
      )
    end
  end
end
