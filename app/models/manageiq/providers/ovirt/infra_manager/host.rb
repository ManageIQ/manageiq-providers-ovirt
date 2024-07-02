class ManageIQ::Providers::Ovirt::InfraManager::Host < ::Host
  def provider_object(connection = nil)
    ManageIQ::Providers::Ovirt::InfraManager::OvirtServices::V4.new(:ems => ext_management_system).get_host_proxy(self, connection)
  end

  supports :update
  supports :capture
  supports :quick_stats do
    unless ext_management_system.supports?(:quick_stats)
      'oVirt API version does not support quick_stats'
    end
  end

  supports :enter_maint_mode do
    if !has_active_ems?
      _('The Host is not connected to an active provider')
    elsif power_state != 'on'
      _('The Host is not powered on')
    end
  end

  supports :exit_maint_mode do
    if !has_active_ems?
      _('The Host is not connected to an active provider')
    elsif power_state != 'maintenance'
      _('The Host is not in maintenance mode')
    end
  end

  def enter_maint_mode
    ext_management_system.ovirt_services.host_deactivate(self)
  end

  def exit_maint_mode
    ext_management_system.ovirt_services.host_activate(self)
  end

  def self.display_name(number = 1)
    n_('Host (oVirt)', 'Hosts (oVirt)', number)
  end

  def params_for_update
    {
      :fields => [
        {
          :component => 'sub-form',
          :id        => 'endpoints-subform',
          :name      => 'endpoints-subform',
          :title     => _("Endpoints"),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :id        => 'remote-tab',
                :name      => 'remote-tab',
                :title     => _('Remote Login'),
                :fields    => [
                  {
                    :component  => 'validate-host-credentials',
                    :id         => 'endpoints.remote.valid',
                    :name       => 'endpoints.remote.valid',
                    :skipSubmit => true,
                    :isRequired => true,
                    :fields     => [
                      {
                        :component  => "text-field",
                        :id         => "authentications.remote.userid",
                        :name       => "authentications.remote.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.remote.password",
                        :name       => "authentications.remote.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :helperText => _('Required if SSH login is disabled for the Default account.')
                      },
                    ],
                  },
                ],
              },
              {
                :component => 'tab-item',
                :id        => 'ws-tab',
                :name      => 'ws-tab',
                :title     => _('Web Service'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :id           => 'wsEnabled',
                    :name         => 'wsEnabled',
                    :skipSubmit   => true,
                    :initialValue => 'disabled',
                    :label        => _('Enabled'),
                    :options      => [
                      {
                        :label => _('Disabled'),
                        :value => 'disabled'
                      },
                      {
                        :label => _('Enabled'),
                        :value => 'enabled',
                      },
                    ],
                  },
                  {
                    :component  => 'validate-host-credentials',
                    :id         => 'endpoints.ws.valid',
                    :name       => 'endpoints.ws.valid',
                    :skipSubmit => true,
                    :condition  => {
                      :when => 'wsEnabled',
                      :is   => 'enabled',
                    },
                    :fields     => [
                      {
                        :component  => "text-field",
                        :id         => "authentications.ws.userid",
                        :name       => "authentications.ws.userid",
                        :label      => _("Username"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.ws.password",
                        :name       => "authentications.ws.password",
                        :label      => _("Password"),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :helperText => _('Used for access to Web Services.')
                      },
                    ],
                  },
                ],
              },
            ]
          ]
        },
      ]
    }
  end
end
