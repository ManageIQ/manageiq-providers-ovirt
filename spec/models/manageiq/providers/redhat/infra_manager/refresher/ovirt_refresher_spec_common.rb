require 'yaml'

module OvirtRefresherSpecCommon
  extend ActiveSupport::Concern

  def serialize_inventory(models = [])
    skip_attributes = %w(updated_on last_refresh_date updated_at last_updated finish_time)
    inventory = {}
    models.each do |model|
      inventory[model.name] = model.all.collect do |rec|
        rec.attributes.except(*skip_attributes)
      end.sort_by { |rec| rec["id"] }
    end
    inventory
  end

  def init_defaults(hostname: "pluto-vdsg.eng.lab.tlv.redhat.com",
                    ipaddress: "10.35.19.13",
                    port: 443,
                    external_network_provider_mock: 'external_network_providers')
    _guid, _server, @zone = EvmSpecHelper.create_guid_miq_server_zone
    create_ems(:hostname => hostname, :ipaddress => ipaddress, :port => port, :zone => @zone, :external_network_provider_mock => external_network_provider_mock)
    init_inventory_wrapper_class
  end

  def create_ems(hostname: "pluto-vdsg.eng.lab.tlv.redhat.com",
                 ipaddress: "10.35.19.13",
                 port: 443,
                 zone: @zone,
                 external_network_provider_mock: 'external_network_providers')
    @ems = FactoryBot.create(:ems_redhat, :zone => zone, :hostname => hostname, :ipaddress => ipaddress,
                             :port => port)
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "pass123"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE

    @ovirt_service = ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4
    allow_any_instance_of(@ovirt_service)
      .to receive(:collect_external_network_providers).and_return(load_response_mock_for(external_network_provider_mock))
  end

  def init_connection_vcr(path_to_recording = nil, is_recording: false)
    allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).and_call_original

    if path_to_recording.present?
      allow(Spec::Support::OvirtSDK::ConnectionVCR).to receive(:new).with(kind_of(Hash)) do |opts|
        Spec::Support::OvirtSDK::ConnectionVCR.new(opts, path_to_recording, is_recording)
      end
    end

    stub_const("OvirtSDK4::Connection", Spec::Support::OvirtSDK::ConnectionVCR)
  end

  def init_inventory_wrapper_class
    @inventory_wrapper_class = ManageIQ::Providers::Redhat::InfraManager::Inventory

    allow_any_instance_of(@inventory_wrapper_class).to(receive(:api).and_return("4.2.0_master."))
    allow_any_instance_of(@inventory_wrapper_class).to(receive(:service)
                                                         .and_return(OpenStruct.new(:version_string => '4.2.0_master.')))
  end

  def load_response_mock_for(filename)
    prefix = described_class.name.underscore
    YAML.load_file(File.join('spec', 'models', prefix, 'response_yamls', filename + '.yml'))
  end
end
