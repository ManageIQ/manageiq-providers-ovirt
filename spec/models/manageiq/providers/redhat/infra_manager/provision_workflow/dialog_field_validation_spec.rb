describe ManageIQ::Providers::Redhat::InfraManager::ProvisionWorkflow::DialogFieldValidation do
  include Spec::Support::WorkflowHelper

  def set_workflow_values
    @workflow.instance_variable_set(:@values, values)
  end

  attr_reader :storage_type

  def values
    {
      :disk_sparsity => @disk_sparsity,
      :disk_format   => @disk_format,
      :linked_clone  => @linked_clone,
      :src_vm_id     => @src_vm_id,
      :src_ems_id    => @src_ems_id
    }
  end

  describe '.validate_disks_configuration' do
    before do
      stub_dialog(:get_dialogs)
      allow_any_instance_of(described_class).to receive(:update_field_visibility)
      admin = FactoryBot.create(:user_with_group)
      @ems = FactoryBot.create(:ems_redhat)
      @template = FactoryBot.create(:template_redhat, :ext_management_system => @ems)

      @storages_on_template = {:file => FactoryBot.create(:storage_nfs, :ext_management_system => @ems), :block => FactoryBot.create(:storage, :store_type => 'iscsi', :ext_management_system => @ems)}

      @hardware = FactoryBot.create(:hardware, :vm_or_template => @template)

      @src_vm_id = @template.id
      @src_ems_id = @ems.id
      @workflow = ManageIQ::Providers::Redhat::InfraManager::ProvisionWorkflow.new(values, admin)
    end

    subject do
      set_workflow_values
      @workflow.validate_disks_configuration({}, {}, {}, {}, {})
    end

    context "linked_clone set to true" do
      before { @linked_clone = true }
      it "does not allow changing format and sparsity" do
        @disk_format = "cow"
        @disk_sparsity = "sparse"
        is_expected.to be_truthy
      end

      it "is valid when default values are set" do
        @disk_format = "default"
        @disk_sparsity = "default"
        is_expected.to be_nil
      end
    end

    context "linked clone is not checked" do
      before do
        @linked_clone = false
      end

      context "with default configurations" do
        before do
          @disk_format = "default"
          @disk_sparsity = "default"
        end

        @allowed_configs = described_class::DISK_CONFIGURATIONS.keys.collect { |configuration| configuration.split(',') }
        @sparsities = ['preallocated', 'sparse']
        @formats = ['cow', 'raw']
        @storage_types = ['file', 'block']

        @allowed_configs.each do |configuration|
          it 'is valid for disks with allowed configurations' do
            storage_type_of_template_disk, disk_format_of_template_disk, disk_sparsity_of_template_disk = configuration
            FactoryBot.create(:disk,
                              :device_name => "disk1",
                              :thin        => disk_sparsity_of_template_disk == 'sparse',
                              :format      => disk_format_of_template_disk,
                              :storage     => @storages_on_template[storage_type_of_template_disk.to_sym],
                              :hardware    => @hardware)
            allow(@workflow).to receive(:dest_storage).and_return(@storages_on_template[storage_type_of_template_disk.to_sym])
            is_expected.to be_nil, "expected to be valid when options are set to default and the disk is configured as: #{configuration}"
          end
        end

        (@storage_types.product(@formats, @sparsities) - @allowed_configs).each do |configuration|
          it 'is not valid for non valid configuration' do
            storage_type_of_template_disk, disk_format_of_template_disk, disk_sparsity_of_template_disk = configuration
            FactoryBot.create(:disk,
                              :device_name => "disk1",
                              :thin        => disk_sparsity_of_template_disk == 'sparse',
                              :format      => disk_format_of_template_disk,
                              :storage     => @storages_on_template[storage_type_of_template_disk.to_sym],
                              :hardware    => @hardware)
            allow(@workflow).to receive(:dest_storage).and_return(@storages_on_template[storage_type_of_template_disk.to_sym])
            is_expected.to be, "expected to be non valid when options are set to default and the disk is configured as: #{configuration}"
          end
        end
      end

      context "non default configurations" do
        @allowed_configs = described_class::DISK_CONFIGURATIONS.keys.collect { |configuration| configuration.split(',') }
        @sparsities = ['preallocated', 'sparse']
        @formats = ['cow', 'raw']
        @storage_types = ['file', 'block']

        @allowed_configs.each do |configuration|
          it 'is valid for allowed configurations' do
            @storage_type, @disk_format, @disk_sparsity = configuration
            FactoryBot.create(:disk,
                              :device_name => "disk1",
                              :thin        => true,
                              :format      => 'cow',
                              :storage     => @storages_on_template[:file],
                              :hardware    => @hardware)
            allow(@workflow).to receive(:dest_storage).and_return(@storages_on_template[@storage_type.to_sym])
            is_expected.to be_nil, "expected to be valid for #{configuration}"
          end
        end

        (@storage_types.product(@formats, @sparsities) - @allowed_configs).each do |configuration|
          it 'is not valid for non valid configurations' do
            @storage_type, @disk_format, @disk_sparsity = configuration
            FactoryBot.create(:disk,
                              :device_name => "disk1",
                              :thin        => true,
                              :format      => 'cow',
                              :storage     => @storages_on_template[:file],
                              :hardware    => @hardware)
            allow(@workflow).to receive(:dest_storage).and_return(@storages_on_template[@storage_type.to_sym])
            is_expected.to be, "expected to be non valid for #{configuration}"
          end
        end
      end
    end
  end
end
