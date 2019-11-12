require 'ostruct'
require 'ovirtsdk4'

describe ManageIQ::Providers::Redhat::Discovery do
  let :ost do
    OpenStruct.new(:ipaddr => "172.168.0.1", :hypervisor => [])
  end

  before(:each) do
    allow(ManageIQ::NetworkDiscovery::Port).to receive(:open?).and_return(true)
  end

  context '.probe' do
    it 'success' do
      allow(OvirtSDK4::Probe).to receive(:exists?).and_return(true)

      described_class.probe(ost)

      expect(ost.hypervisor).to eq [:rhevm]
    end

    it 'failure' do
      allow(OvirtSDK4::Probe).to receive(:exists?).and_return(false)

      described_class.probe(ost)

      expect(ost.hypervisor).to be_empty
    end
  end

  context 'error' do
    it 'connection error' do
      allow(OvirtSDK4::Probe).to receive(:exists?).and_raise(OvirtSDK4::ConnectionError)

      described_class.probe(ost)

      expect(ost.hypervisor).to be_empty
    end

    it 'generic ovirtsdk4 error' do
      allow(OvirtSDK4::Probe).to receive(:exists?).and_raise(OvirtSDK4::Error)

      described_class.probe(ost)

      expect(ost.hypervisor).to be_empty
    end
  end
end
