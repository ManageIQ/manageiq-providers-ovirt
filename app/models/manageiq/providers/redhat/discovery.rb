require 'manageiq/network_discovery/port'
require 'ovirt'

module ManageIQ
  module Providers
    module Redhat
      class Discovery
        def self.probe(ost)
          ::Ovirt.logger = $rhevm_log if $rhevm_log

          if ManageIQ::NetworkDiscovery::Port.open?(ost, ::Ovirt::Service::DEFAULT_PORT) &&
             ::Ovirt::Service.ovirt?(:server => ost.ipaddr, :verify_ssl => false)
            ost.hypervisor << :rhevm
          end
        end
      end
    end
  end
end
