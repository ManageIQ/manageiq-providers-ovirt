describe ManageIQ::Providers::Redhat::InfraManager::EventParser do
  context 'parse event' do
    let(:ip_address) { '192.168.1.105' }

    before(:each) do
      _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryBot.create(:ems_redhat, :zone => zone, :hostname => "192.168.1.105", :ipaddress => "192.168.1.105",
                                :port => 8443)
      @ems.update_authentication(:default => {:userid => "admin@internal", :password => "engine"})
      @ems.default_endpoint.path = "/ovirt-engine/api"
      stub_settings_merge(
        :ems => {
          :ems_redhat => {
            :resolve_ip_addresses => false
          }
        }
      )
    end

    require 'yaml'
    def load_response_mock_for(filename)
      prefix = described_class.name.underscore
      YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
    end

    before(:each) do
      inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4
      stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => true } })
      user_mock = load_response_mock_for('user')
      allow_any_instance_of(inventory_wrapper_class)
        .to receive(:username_by_href).and_return("#{user_mock.name}@#{user_mock.domain.name}")
      allow_any_instance_of(inventory_wrapper_class).to receive(:api).and_return("4.2.0_master")
      allow_any_instance_of(inventory_wrapper_class).to receive(:service)
        .and_return(OpenStruct.new(:version_string => '4.2.0_master'))
    end

    it "should parse event" do
      event_xml =
        '<event href="/ovirt-engine/api/events/16359" id="16359">
<description>VM new_vm configuration was updated by admin@internal-authz.</description>
<code>35</code>
<correlation_id>4e787afc-ed42-4193-82a0-66943860d142</correlation_id>
<custom_id>-1</custom_id>
<flood_rate>30</flood_rate>
<origin>oVirt</origin>
<severity>normal</severity>
<time>2017-05-07T15:45:05.485+03:00</time>
<cluster href="/ovirt-engine/api/clusters/504ae500-3476-450e-8243-f6df0f7f7acf" id="504ae500-3476-450e-8243-f6df0f7f7acf"/>
<data_center href="/ovirt-engine/api/datacenters/b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1" id="b60b3daa-dcbd-40c9-8d09-3fc08c91f5d1"/>
<template href="/ovirt-engine/api/templates/785e845e-baa0-4812-8a8c-467f37ad6c79" id="785e845e-baa0-4812-8a8c-467f37ad6c79"/>
<user href="/ovirt-engine/api/users/0000002c-002c-002c-002c-000000000149" id="0000002c-002c-002c-002c-000000000149"/>
<vm href="/ovirt-engine/api/vms/78e60d40-1fd9-42e7-aa07-4ef4439b5289" id="78e60d40-1fd9-42e7-aa07-4ef4439b5289"/>
</event>'

      event = OvirtSDK4::Reader.read(event_xml)
      allow(ManageIQ::Providers::Redhat::InfraManager).to receive(:find_by).with(:id => @ems.id).and_return(@ems)
      ManageIQ::Providers::Redhat::InfraManager::EventFetcher.new(@ems).set_event_name!(event)
      parsed = described_class.event_to_hash(event, @ems.id)
      expect(parsed).to include(
        :event_type => "USER_UPDATE_VM",
        :source     => 'RHEVM',
        :message    => "VM new_vm configuration was updated by admin@internal-authz.",
        :timestamp  => Time.zone.parse("2017-05-07T15:45:05.485+03:00"),
        :username   => "admin@internal-authz",
        :full_data  => event,
        :ems_id     => @ems.id,
      )
    end
  end
end
