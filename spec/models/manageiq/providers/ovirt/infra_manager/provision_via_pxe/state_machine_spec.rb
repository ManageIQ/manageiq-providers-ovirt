describe ManageIQ::Providers::Ovirt::InfraManager::ProvisionViaPxe do
  context "::StateMachine" do
    before do
      ems      = FactoryBot.create(:ems_ovirt_with_authentication)
      template = FactoryBot.create(:template_ovirt, :ext_management_system => ems)
      @vm = FactoryBot.create(:vm_ovirt, :ext_management_system => ems)
      options = {:src_vm_id => template.id}
      @task = FactoryBot.create(:miq_provision_ovirt_via_pxe, :source => template, :destination => @vm,
                                 :state => 'pending', :status => 'Ok', :options => options)
      allow(@task).to receive(:destination_image_locked?).and_return(false)
      @ovirt_services = double("ovirt_services")
      allow(ems).to receive(:ovirt_services).and_return(@ovirt_services)
      allow(@ovirt_services).to receive(:get_mac_address_of_nic_on_requested_vlan).and_return("some_mac_address")
      allow(@task).to receive(:update_and_notify_parent).and_return(nil)
    end

    include_examples "common rhev state machine methods"

    it "#configure_destination" do
      expect(@task).to receive(:create_pxe_configuration_file)
      @task.configure_destination
    end

    describe "#boot_from_network" do
      context "vm is ready" do
        before do
          allow(@ovirt_services).to receive(:vm_boot_from_network).with(@task).and_return(nil)
        end

        it "#powered_on_in_provider?" do
          expect(@ovirt_services).to receive(:powered_on_in_provider?).with(@vm)
          @task.boot_from_network
        end
      end

      context "vm is not ready" do
        before do
          exception = ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::VmNotReadyToBoot
          allow(@ovirt_services).to receive(:vm_boot_from_network).with(@task)
            .and_raise(exception)
        end

        it "requeues the phase" do
          expect(@task).to receive(:requeue_phase)
          @task.boot_from_network
        end
      end
    end
  end
end
