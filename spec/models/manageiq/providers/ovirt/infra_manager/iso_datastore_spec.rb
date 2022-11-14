RSpec.describe ManageIQ::Providers::Ovirt::InfraManager::IsoDatastore do
  include Spec::Support::ArelHelper

  let(:ems) { FactoryBot.create(:ems_redhat) }
  let(:iso_datastore) { FactoryBot.create(:iso_datastore, :ext_management_system => ems, :name => ems.name) }

  describe "#advertised_images" do
    subject(:advertised_images) { ems.ovirt_services.advertised_images }

    context "ems is rhv" do
      context "supports api4" do
        it "send the method to ovirt services v4" do
          expect_any_instance_of(ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4)
            .to receive(:advertised_images)
          advertised_images
        end
      end
    end

    describe "#name" do
      it "has a name" do
        expect(iso_datastore.name).to eq(ems.name)
      end

      it "fetches name via sql" do
        iso_datastore
        expect(virtual_column_sql_value(Storage, "name")).to eq(ems.name)
      end
    end
  end
end
