RSpec.configure do |config|
  config.before(:each) do
    allow(Socket).to receive(:getaddrinfo).and_return([["AF_INET", 0, "10.35.18.14", "10.35.18.14", 2, 1, 6], ["AF_INET", 0, "10.35.18.14", "10.35.18.14", 2, 2, 17], ["AF_INET", 0, "10.35.18.14", "10.35.18.14", 2, 3, 0]])
  end
end

if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Ovirt::Engine.root, 'spec/vcr_cassettes')
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
Dir[ManageIQ::Providers::Ovirt::Engine.root.join("spec/support/**/*.rb")].each { |f| require f }
