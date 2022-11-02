describe ManageIQ::Providers::Ovirt::InfraManager::Provision::StateMachine do
  include MiqProvision::StateMachineSpecHelper
  let(:cluster)  { FactoryBot.create(:ems_cluster, :ext_management_system => ems) }
  let(:ems)      do
    _, _, zone = EvmSpecHelper.create_guid_miq_server_zone
    FactoryBot.create(:ems_ovirt_with_authentication, :zone => zone)
  end
  let(:disk_attachments_service) { double("disk_attachments_service", :add => nil) }
  let(:rhevm_vm) { double("RHEVM VM") }
  let(:task)     { request.tap(&:create_request_tasks).miq_request_tasks.first }
  let(:template) { FactoryBot.create(:template_ovirt, :ext_management_system => ems) }
  let(:storages) { double("storages") }
  let(:storage_name) { "abc" }
  let(:host) { double("hostgig", :writable_storages => storages) }
  let(:hosts) { [host] }
  let(:vm) do
    FactoryBot.create(:vm_ovirt, :ext_management_system => ems, :raw_power_state => "on").tap do |v|
      allow(v).to receive(:with_provider_object).and_yield(rhevm_vm)
      allow(ems).to receive(:with_disk_attachments_service).with(v).and_return(disk_attachments_service)
      allow(ems).to receive(:with_provider_connection).and_return(false)
      allow(ems).to receive(:storages).and_return(storages)
      allow(storages).to receive(:find_by).with({:name => storage_name}).and_return(storage)
      allow(ems).to receive(:hosts).and_return(hosts)
    end
  end

  let(:storage) do
    FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ", :name => storage_name)
  end

  let(:storage) do
    FactoryBot.create(:storage_nfs, :ems_ref => "http://example.com/storages/XYZ", :name => storage_name)
  end

  let(:options) do
    {
      :dest_cluster           => [cluster.id, cluster.name],
      :number_of_vms          => 1,
      :placement_cluster_name => [cluster.id, cluster.name],
      :src_vm_id              => template.id,
      :vm_auto_start          => true,
      :vm_description         => "some description",
      :vm_target_name         => "test_vm_1",
      :disk_scsi              => [
        {
          :disk_size_in_mb  => "33",
          :persistent       => true,
          :thin_provisioned => true,
          :dependent        => true,
          :bootable         => false,
          :datastore        => storage.name
        }
      ]
    }
  end

  let(:request) do
    FactoryBot.create(:miq_provision_request, :requester => FactoryBot.create(:user_with_group), :src_vm_id => template.id, :options => options).tap do |request|
      allow(request).to receive(:automate_event_failed?).and_return(false)
    end
  end

  let(:expected_states_with_counts) do
    {
      :create_destination                       => {:signals => 1, :calls => 1},
      :determine_placement                      => {:signals => 1, :calls => 1},
      :prepare_provision                        => {:signals => 1, :calls => 1},
      :start_clone_task                         => {:signals => 1, :calls => 1},
      :poll_clone_complete                      => {:signals => 1, :calls => 3},
      :poll_destination_in_vmdb                 => {:signals => 1, :calls => 3},
      :customize_destination                    => {:signals => 1, :calls => 3},
      :configure_disks                          => {:signals => 1, :calls => 1},
      :poll_add_disks_complete                  => {:signals => 1, :calls => 1},
      :customize_guest                          => {:signals => 1, :calls => 1},
      :poll_destination_powered_off_in_provider => {:signals => 1, :calls => 4},
      :poll_destination_powered_off_in_vmdb     => {:signals => 2, :calls => 2},
      :post_provision                           => {:signals => 1, :calls => 1},
      :autostart_destination                    => {:signals => 1, :calls => 2},
      :post_create_destination                  => {:signals => 2, :calls => 1},
      :mark_as_completed                        => {:signals => 1, :calls => 1},
      :finish                                   => {:signals => 1, :calls => 1},
    }
  end

  context "version 4" do
    ## BRANCH STATES
    def test_autostart_destination_with_use_cloud_init
      task.phase_context[:boot_with_cloud_init] = true

      expect(rhevm_vm).to receive(:start).with({:use_cloud_init => an_instance_of(CustomAttribute)})

      call_method
    end

    def test_autostart_destination_without_use_cloud_init
      task.phase_context.delete(:boot_with_cloud_init)

      expect(rhevm_vm).not_to receive(:start).with({:use_cloud_init => an_instance_of(CustomAttribute)})

      call_method
    end

    def test_autostart_destination_with_sysprep
      task.phase_context[:boot_with_sysprep] = true

      expect(rhevm_vm).to receive(:start).with({:use_sysprep => an_instance_of(CustomAttribute)})

      call_method
    end

    def test_autostart_destination_without_sysyprep
      task.phase_context.delete(:boot_with_sysprep)

      expect(rhevm_vm).not_to receive(:start).with({:use_sysprep => an_instance_of(CustomAttribute)})

      call_method
    end

    include_examples "End-to-end State Machine Run"
  end

  def test_customize_guest
    call_method
  end

  def test_create_destination
    call_method
  end

  def test_determine_placement
    call_method
  end

  def test_start_clone_task
    expect(task).to receive(:start_clone)

    call_method
  end

  def test_poll_clone_complete
    @test_poll_clone_complete_setup ||= begin
                                          expect(task).to receive(:clone_complete?).and_return(false, false, true)
                                          expect(task).to receive(:requeue_phase).twice { requeue_phase }
                                          # make sure that full refresh is not run
                                          expect(EmsRefresh).not_to receive(:queue_refresh).with(no_args)
                                        end

    call_method
  end

  def test_customize_destination
    expect(task.destination).to be_kind_of(ManageIQ::Providers::Ovirt::InfraManager::Vm) # TODO: For previous state

    @test_customize_destination_setup ||= begin
                                            expect(task).to receive(:requeue_phase).twice { requeue_phase }
                                            expect(task).to receive(:destination_image_locked?).and_return(true, true, false)
                                            expect(task).to receive(:configure_container)
                                          end

    call_method
  end

  def test_autostart_destination
    expect(vm).to receive(:start).twice { vm.raw_start }
    test_autostart_destination_with_use_cloud_init
    test_autostart_destination_without_use_cloud_init
  end

  def test_configure_disks
    call_method
  end

  def test_poll_add_disks_complete
    call_method
  end
end
