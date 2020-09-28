describe ManageIQ::Providers::Redhat::InfraManager::Host do
  require 'ovirtsdk4'
  describe '#quickStats' do
    let(:ems) { FactoryBot.create(:ems_redhat_with_authentication) }
    subject { FactoryBot.create(:host_redhat, :ems_id => ems.id) }

    it '.supports_quick_stats?' do
      allow(subject.ext_management_system).to receive(:api_version).and_return('4.2.4')
      expect(subject.supports_quick_stats?).to be true
    end

    it 'calls list on StatisticsService' do
      allow(subject.ext_management_system).to receive(:api_version).and_return('4.3.6')
      expect_any_instance_of(OvirtSDK4::StatisticsService).to receive(:list)
      subject.quickStats
    end
  end
end
