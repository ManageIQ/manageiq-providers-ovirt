describe ManageIQ::Providers::Redhat::InfraManager::Provision::Configuration do
  let(:cust_template) { FactoryBot.create(:customization_template_cloud_init, :script => '#some_script') }
  let(:ems)           { FactoryBot.create(:ems_redhat_with_authentication) }
  let(:host)          { FactoryBot.create(:host_redhat) }
  let(:task)          { FactoryBot.create(:miq_provision_redhat, :state => 'pending', :status => 'Ok', :options => {:src_vm_id => template.id}) }
  let(:template)      { FactoryBot.create(:template_redhat, :ext_management_system => ems) }
  let(:vm)            { FactoryBot.create(:vm_redhat, :ext_management_system => ems) }

  before { allow_any_instance_of(ManageIQ::Providers::Redhat::InfraManager::Provision).to receive(:with_provider_destination).and_yield(provider_object) }
  context "#attach_floppy_payload" do
    context "with ovirtsdk4" do
      let(:vm_proxy)        { OvirtSDK4::Vm.new }
      let(:vm_service)      { double("OvirtSDK4::VmService", :get => vm_proxy) }
      let(:connection)      { double("OvirtSDK4::Connection") }
      let(:ovirt_services)  { double("ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4") }
      let(:provider_object) { ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4::VmProxyDecorator.new(vm_service, connection, ovirt_services) }

      it "updates the vm with the right payload" do
        task.options[:customization_template_id] = cust_template.id
        expect(task).to     receive(:prepare_customization_template_substitution_options).and_return('key' => 'value')

        expect(vm_service).to receive(:update) do |vm|
          expect(vm.payloads.count).to eq(1)
          payloads = vm.payloads
          payload = payloads.first
          files = payload.files
          file = files.first
          expect(payloads.count).to eq(1)
          expect(payload.type).to eq("floppy")
          expect(files.count).to eq(1)
          expect(file.name).to eq(cust_template.default_filename)
          expect(file.content).to eq("#some_script")
        end

        task.attach_floppy_payload
      end
    end
  end

  context "#configure_sysprep" do
    let(:vm_service)     { double("OvirtSDK4::VmService") }
    let(:connection)     { double("OvirtSDK4::Connection") }
    let(:ovirt_services) { double("ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4") }
    let(:provider_object) { ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4::VmProxyDecorator.new(vm_service, connection, ovirt_services) }

    it "should configure sysprep" do
      task.options[:customization_template_id] = cust_template.id
      allow(task).to receive(:get_option).and_return("#some_script")

      expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(
                                                    :initialization => {
                                                      :custom_script => '#some_script'
                                                    }
      ))

      task.configure_sysprep

      expect(task.phase_context[:boot_with_sysprep]).to eq(true)
    end

    let(:cust_template) { FactoryBot.create(:customization_template_sysprep, :script => "the script: <%= evm[:replace_me] %>") }

    it "provisions sysprep from template with substitutions" do
      allow(MiqRegion).to receive_message_chain(:my_region, :remote_ui_url => "1.1.1.1")
      allow(MiqRegion).to receive_message_chain(:my_region, :maintenance_zone => nil)

      task.options[:sysprep_enabled] = ["fields", "Sysprep Specification"]
      task.options[:customization_template_id] = cust_template.id
      task.options[:replace_me] = "replaced!"

      expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(
                                                    :initialization => {
                                                      :custom_script => "the script: replaced!"
                                                    }
      ))

      task.configure_sysprep
    end

    context "with timezone set" do
      let(:cust_template) { FactoryBot.create(:customization_template_sysprep, :script => "timezone: <%= evm[:sysprep_timezone] %>") }

      it "it properly substitutes timezone when it is set" do
        allow(MiqRegion).to receive_message_chain(:my_region, :remote_ui_url => "1.1.1.1")
        allow(MiqRegion).to receive_message_chain(:my_region, :maintenance_zone => nil)

        task.options[:sysprep_enabled] = ["fields", "Sysprep Specification"]
        task.options[:customization_template_id] = cust_template.id
        task.options[:sysprep_timezone] = ["300", "(GMT+13:00) Nuku'alofa"]

        expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(
                                                      :initialization => {
                                                        :custom_script => "timezone: Nuku'alofa"
                                                      }
        ))

        task.configure_sysprep
      end

      it "it properly substitutes timezone when it is not set" do
        allow(MiqRegion).to receive_message_chain(:my_region, :remote_ui_url => "1.1.1.1")
        allow(MiqRegion).to receive_message_chain(:my_region, :maintenance_zone => nil)

        task.options[:sysprep_enabled] = ["fields", "Sysprep Specification"]
        task.options[:customization_template_id] = cust_template.id
        task.options[:sysprep_timezone] = nil

        expect(vm_service).to receive(:update).with(OvirtSDK4::Vm.new(
                                                      :initialization => {
                                                        :custom_script => "timezone: "
                                                      }
        ))

        task.configure_sysprep
      end
    end
  end
end
