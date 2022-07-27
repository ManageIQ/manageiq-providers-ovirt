describe ManageIQ::Providers::Ovirt::InfraManager::MetricsCapture do
  require 'ovirt_metrics'

  context "#perf_capture_object" do
    let(:ems) { FactoryBot.create(:ems_ovirt_with_metrics_authentication) }
    let(:host) { FactoryBot.create(:host_ovirt, :ems_id => ems.id) }
    it "returns the correct class" do
      expect(host.perf_capture_object.class).to eq(described_class)
    end
  end

  context '#perf_collect_metrics' do
    let(:ems) { FactoryBot.create(:ems_ovirt_with_metrics_authentication) }
    let(:host) { FactoryBot.create(:host_ovirt, :ems_id => ems.id) }
    let(:start_time) { 4.hours.ago }
    it 'collects historical metric data according to the value of historical_start_time' do
      allow(Metric::Capture).to receive(:historical_start_time).and_return(start_time)
      allow(OvirtMetrics).to receive(:establish_connection).and_return(true)
      allow_any_instance_of(ManageIQ::Providers::Ovirt::InfraManager).to receive(:history_database_name)
                                                                      .and_return('stuff')
      expect(OvirtMetrics).to receive(:host_realtime).with(host.uid_ems, start_time, nil)
      host.perf_collect_metrics("realtime")
    end

    context 'ems has no metrics authentication' do
      let(:ems) { FactoryBot.create(:ems_ovirt) }
      it 'returns empty results when no credentials are defined' do
        expect(host.perf_collect_metrics("realtime")).to eq([{}, {}])
      end
    end
  end
end
