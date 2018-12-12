describe ManageIQ::Providers::Redhat::InfraManager::Host do
  require 'ovirtsdk4'
  describe '#quickStats' do
    let(:ems) { FactoryBot.create(:ems_redhat_with_authentication) }
    subject { FactoryBot.create(:host_redhat, :ems_id => ems.id) }
    before(:each) do
      allow_any_instance_of(ManageIQ::Providers::Redhat::InfraManager)
        .to receive(:supported_api_versions).and_return([4])
    end
    it '.supports_quick_stats?' do
      expect(subject.supports_quick_stats?).to be true
    end

    it 'calls list on StatisticsService' do
      expect_any_instance_of(OvirtSDK4::StatisticsService).to receive(:list)
      subject.quickStats
    end
  end
end
