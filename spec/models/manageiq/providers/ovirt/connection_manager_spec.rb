require 'ovirtsdk4'

describe ManageIQ::Providers::Ovirt::ConnectionManager do
  #
  # This is a dummy connection class that remember the connection options, so that we can inspect
  # them.
  #
  class GoodDummyConnection
    attr_reader :options

    def initialize(opts)
      @options = opts
      @closed = false
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end
  end

  #
  # This is a dummy connection class that raises an error when trying to close a connection, so tha
  # twe can verify the behaviour of the manager in that case.
  #
  class BadDummyConnection
    def initialize(opts)
    end

    def close
      raise OvirtSDK4::Error, 'myerror'
    end

    def closed?
      false
    end
  end

  def use_good_dummy_connection
    allow(OvirtSDK4::Connection).to receive(:new) { |opts| GoodDummyConnection.new(opts) }
  end

  def use_bad_dummy_connection
    allow(OvirtSDK4::Connection).to receive(:new) { |opts| BadDummyConnection.new(opts) }
  end

  let(:manager) { described_class.new }

  describe '#get' do
    it 'creates connections with the options given' do
      use_good_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      connection = manager.get('mykey', options)
      expect(connection.options).to eql(options)
    end

    it 'reuses the connection for same key and same options' do
      use_good_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      first = manager.get('mykey', options)
      second = manager.get('mykey', options)
      expect(second).to equal(first)
    end

    it 'creates different connections for different keys and same options' do
      use_good_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      first = manager.get('mykey', options)
      second = manager.get('yourkey', options)
      expect(second).not_to equal(first)
    end

    it 'creates new connection for same key and different options' do
      use_good_dummy_connection
      first_options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      second_options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'newpass'
      }
      first = manager.get('mykey', first_options)
      second = manager.get('mykey', second_options)
      expect(second).not_to equal(first)
      expect(first.closed?).to be(true)
    end

    it 'creates a new connection if the previous one has been explicitly closed' do
      use_good_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      first = manager.get('mykey', options)
      manager.close('mykey')
      second = manager.get('mykey', options)
      expect(second).to_not equal(first)
    end
  end

  describe '#close' do
    it 'closes the connection' do
      use_good_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      connection = manager.get('mykey', options)
      manager.close('mykey')
      expect(connection.closed?).to be(true)
    end
  end

  describe '#clear' do
    it 'closes all the connections' do
      use_good_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      first = manager.get('mykey', options)
      second = manager.get('yourkey', options)
      manager.clear
      expect(first.closed?).to be(true)
      expect(second.closed?).to be(true)
    end

    it 'ignores exceptions raised when closing connections' do
      use_bad_dummy_connection
      options = {
        :url      => 'myurl',
        :username => 'myuser',
        :password => 'mypass'
      }
      manager.get('mykey', options)
      manager.get('yourkey', options)
      manager.clear
    end
  end
end
