require 'manageiq/network_discovery/port'
require 'ovirtsdk4'

module ManageIQ
  module Providers
    module Ovirt
      class Discovery
        OVIRT_DEFAULT_PORT = 443

        class << self
          def probe(ost)
            if ManageIQ::NetworkDiscovery::Port.open?(ost, OVIRT_DEFAULT_PORT) &&
               ovirt_exists?(ost.ipaddr, $rhevm_log)
              ost.hypervisor << :rhevm
            end
          end

          private

          def ovirt_exists?(host, logger = nil)
            opts = {
              :host => host,
              :log  => logger
            }.compact
            OvirtSDK4::Probe.exists?(opts)
          rescue OvirtSDK4::Error
            false
          end
        end
      end
    end
  end
end
