describe ManageIQ::Providers::Redhat::InfraManager::FuturesCollector do
  let(:future_collection) { FutureCollection.new }
  let(:keyed_requests) { [] }
  let(:futures) { [] }
  before do
    (1..10).each do |i|
      f = future_collection.new_future("f_#{i}")
      futures << f
      keyed_requests << future_collection.create_keyed_request("key_#{i}", f)
    end
  end

  context 'no failure' do
    it 'calls wait on all futures' do
      futures.each do |f|
        expect(f).to receive(:wait).and_call_original
      end
      described_class.process_keyed_requests_queue(keyed_requests, 5)
    end
  end

  context 'exception in future' do
    before do
      prc = proc do
        raise "Exception"
      end
      f = future_collection.new_future("f", prc)
      keyed_requests.insert(4, future_collection.create_keyed_request("key", f))
    end

    it 'calls wait on all pending futures' do
      futures[0, 7].each do |f|
        expect(f).to receive(:wait).and_call_original
      end
      described_class.process_keyed_requests_queue(keyed_requests, 4)
    end

    it 'does not process pending keyed requests' do
      keyed_requests[8, 9].each do |kr|
        expect(kr.first[1]).not_to receive(:call)
      end
      described_class.process_keyed_requests_queue(keyed_requests, 4)
    end
  end

  context 'exception in processing request' do
    before do
      prc = proc do
        raise "Exception"
      end
      keyed_requests[4]["key_5"] = prc
    end

    it 'calls wait on all pending futures' do
      futures[0, 4].each do |f|
        expect(f).to receive(:wait).and_call_original
      end
      described_class.process_keyed_requests_queue(keyed_requests, 4)
    end

    it 'does not process pending keyed requests' do
      keyed_requests[5, 9].each do |kr|
        expect(kr.first[1]).not_to receive(:call)
      end
      described_class.process_keyed_requests_queue(keyed_requests, 4)
    end
  end
end

class FutureCollection
  attr_reader :futures

  def initialize
    @futures = []
  end

  def new_future(name, blk = nil)
    f = Future.new(self, name, blk)
    futures << f
    f
  end

  def create_keyed_request(key, future = nil)
    procedure = proc do
      future || new_future(key)
    end
    { key => procedure}
  end

  class Future
    attr_reader :future_collection, :name, :blk_to_execute

    def initialize(future_collection, name, blk_to_execute = nil)
      @blk_to_execute = blk_to_execute
      @future_collection = future_collection
      @name = name
    end

    def wait
      blk_to_execute.call if blk_to_execute
    end
  end
end
