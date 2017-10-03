module Spec::Support::OvirtSDK
  require 'ovirtsdk4'
  class ConnectionVCR < OvirtSDK4::Connection
    attr_accessor :all_req_hash
    attr_reader :path_to_recording, :is_recording
    DEFAULT_REC_PATH = 'spec/vcr_cassettes/manageiq/providers/redhat/infra_manager/refresh/ovirt_sdk_refresh_recording.yml'.freeze
    def initialize(opts = {}, path_to_recording = DEFAULT_REC_PATH, is_recording = false)
      @all_req_hash = {}
      @path_to_recording = path_to_recording
      @is_recording = is_recording
      if File.file?(path_to_recording) && !opts[:force_recording]
        @all_req_hash = YAML.load_file(path_to_recording)
      end
      super(opts)
    end

    def wait(request)
      req_key = "#{request.url}#{request.query}#{request.method}#{request.body}"
      @all_req_hash[req_key] ||= []
      res = @all_req_hash[req_key].shift
      return http_response_hash_to_obj(res) if res
      res = super(request)
      @all_req_hash[req_key] << http_response_to_hash(res)
      File.write(path_to_recording, @all_req_hash.to_yaml)
      res
    end

    def create_access_token
      return "access" unless is_recording
      super
    end

    def http_response_to_hash(http_response)
      {
        :body    => http_response.body,
        :code    => http_response.code,
        :headers => http_response.headers,
        :message => http_response.message
      }
    end

    def http_response_hash_to_obj(http_response_hash)
      OvirtSDK4::HttpResponse.new(http_response_hash)
    end
  end
end
