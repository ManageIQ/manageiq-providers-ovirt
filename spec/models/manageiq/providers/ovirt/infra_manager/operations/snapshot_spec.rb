describe ManageIQ::Providers::Ovirt::InfraManager::Vm::Operations::Snapshot do
  describe 'calling snapshot operations' do
    let(:vm) { FactoryBot.create(:vm_ovirt) }
    let!(:snapshot) { double("snapshot", :id => 1, :uid_ems => 'ems_id_111') }
    before(:each) do
      @snapshot_service = double('snapshot_service')
      @snapshots_service = double('snapshots_service')
      allow(@snapshots_service).to receive(:snapshot_service)
        .with(snapshot.uid_ems) { @snapshot_service }
      allow(vm).to receive(:with_snapshots_service).with(any_args).and_yield(@snapshots_service)
      allow(vm).to receive(:snapshots).and_return(double(:find_by => snapshot))
    end

    it 'calls remove on the snapshot service' do
      expect(@snapshot_service).to receive(:remove)
      vm.raw_remove_snapshot(snapshot.id)
    end

    it 'calls revert on the snapshot service' do
      expect(@snapshot_service).to receive(:restore)
      vm.raw_revert_to_snapshot(snapshot.id)
    end

    it 'calls revert on the snapshot service' do
      expect(@snapshots_service).to receive(:add)
        .with(:description => "snap_desc", :persist_memorystate => true)
      vm.raw_create_snapshot(nil, "snap_desc", true)
    end
  end

  describe 'supported above api v4' do
    let(:ems) { FactoryBot.create(:ems_ovirt_with_authentication, :api_version => '4.3.6') }
    let(:vm)  { FactoryBot.create(:vm_ovirt, :ext_management_system => ems) }
    subject { vm.supports?(:snapshots) }
    context 'when engine supports v4 api' do
      it { is_expected.to be_truthy }
    end
  end

  describe "#revert_to_snapshot_denied_message" do
    let(:ems) { FactoryBot.create(:ems_ovirt_with_authentication) }
    let(:vm)  { FactoryBot.create(:vm_ovirt, :ext_management_system => ems) }
    let(:allowed_to_revert) { true }
    let(:active) { true }
    subject { vm.revert_to_snapshot_denied_message(active) }
    before do
      allow(vm).to receive(:allowed_to_revert?).and_return(allowed_to_revert)
    end

    context "allowed to revert" do
      context "active snapshot" do
        it { is_expected.to eq("Revert is not allowed for a snapshot that is the active one") }
      end

      context "inactive snapshot" do
        let(:active) { false }
        it { is_expected.to eq(nil) }
      end
    end

    context "not allowed to revert" do
      let(:allowed_to_revert) { false }
      context "active snapshot" do
        it { is_expected.to eq("Revert is allowed only when vm is down. Current state is on") }
      end

      context "inactive snapshot" do
        let(:active) { false }
        it { is_expected.to eq("Revert is allowed only when vm is down. Current state is on") }
      end
    end
  end
end
