module ManageIQ
  module Providers
    module Ovirt
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Ovirt

        config.autoload_paths << root.join('lib').to_s

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('oVirt Provider')
        end
      end
    end
  end
end
