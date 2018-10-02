describe ManageIQ::Providers::Redhat::Discovery do
  it ".probe" do
    require 'ostruct'
    allow(ManageIQ::NetworkDiscovery::Port).to receive(:open?).and_return(true)
    allow(::Ovirt::Service).to receive(:ovirt?).and_return(true)
    ost = OpenStruct.new(:ipaddr => "172.168.0.1", :hypervisor => [])
    described_class.probe(ost)
    expect(ost.hypervisor).to eq [:rhevm]
  end
end
