describe 'update_cloud_init!' do
  let(:service) { double }
  let(:connection) { double }
  let(:services) { double }
  let(:proxy) { ManageIQ::Providers::Redhat::InfraManager::OvirtServices::V4::VmProxyDecorator.new(service, connection, services) }

  it 'does nothing if the script is empty' do
    expect(service).not_to receive(:update)
    proxy.update_cloud_init!('')
  end

  it 'does nothing if the script is nil' do
    expect(service).not_to receive(:update)
    proxy.update_cloud_init!(nil)
  end

  it 'extracts the values that need special treatment' do
    script = <<~OPTIONS
      active_directory_ou: my_active_directory_ou
      authorized_ssh_keys: my_authorized_ssh_keys
      dns_search: my_dns_search
      dns_servers: my_dns_servers
      domain: my_domain
      host_name: my_host_name
      input_locale: my_input_locale
      org_name: my_org_name
      regenerate_ssh_keys: true
      root_password: my_root_password
      system_locale: my_system_locale
      timezone: my_timezone
      ui_language: my_ui_language
      user_locale: my_user_locale
      user_name: my_user_name
    OPTIONS
    expect(service).to receive(:update) do |vm|
      expect(vm.initialization.active_directory_ou).to eq('my_active_directory_ou')
      expect(vm.initialization.authorized_ssh_keys).to eq('my_authorized_ssh_keys')
      expect(vm.initialization.dns_search).to eq('my_dns_search')
      expect(vm.initialization.dns_servers).to eq('my_dns_servers')
      expect(vm.initialization.domain).to eq('my_domain')
      expect(vm.initialization.host_name).to eq('my_host_name')
      expect(vm.initialization.input_locale).to eq('my_input_locale')
      expect(vm.initialization.org_name).to eq('my_org_name')
      expect(vm.initialization.regenerate_ssh_keys).to be(true)
      expect(vm.initialization.root_password).to eq('my_root_password')
      expect(vm.initialization.system_locale).to eq('my_system_locale')
      expect(vm.initialization.timezone).to eq('my_timezone')
      expect(vm.initialization.ui_language).to eq('my_ui_language')
      expect(vm.initialization.user_locale).to eq('my_user_locale')
      expect(vm.initialization.user_name).to eq('my_user_name')
    end
    proxy.update_cloud_init!(script)
  end

  it 'does not assign values to attributes that are not part of the cloud-init script' do
    script = <<~OPTIONS
      not_special: my_value
    OPTIONS
    expect(service).to receive(:update) do |vm|
      expect(vm.initialization.active_directory_ou).to be_nil
      expect(vm.initialization.authorized_ssh_keys).to be_nil
      expect(vm.initialization.dns_search).to be_nil
      expect(vm.initialization.dns_servers).to be_nil
      expect(vm.initialization.domain).to be_nil
      expect(vm.initialization.host_name).to be_nil
      expect(vm.initialization.input_locale).to be_nil
      expect(vm.initialization.nic_configurations).to be_nil
      expect(vm.initialization.org_name).to be_nil
      expect(vm.initialization.regenerate_ssh_keys).to be_nil
      expect(vm.initialization.root_password).to be_nil
      expect(vm.initialization.system_locale).to be_nil
      expect(vm.initialization.timezone).to be_nil
      expect(vm.initialization.ui_language).to be_nil
      expect(vm.initialization.user_locale).to be_nil
      expect(vm.initialization.user_name).to be_nil
    end
    proxy.update_cloud_init!(script)
  end

  it 'extracts the nested values that need special treatment' do
    script = <<~CONFS
      nic_configurations:
      - name: eth0
        on_boot: true
        boot_protocol: dhcp
      - name: eth1
        on_boot: false
        boot_protocol: static
        ip:
          version: v4
          address: 192.168.122.100
          netmask: 255.255.255.0
          gateway: 192.168.122.1
    CONFS
    expect(service).to receive(:update) do |vm|
      nics = vm.initialization.nic_configurations
      expect(nics).not_to be_nil
      expect(nics.length).to be(2)
      nic0 = nics[0]
      expect(nic0.name).to eq('eth0')
      expect(nic0.on_boot).to be(true)
      expect(nic0.boot_protocol).to eq(OvirtSDK4::BootProtocol::DHCP)
      expect(nic0.ip).to be_nil
      nic1 = nics[1]
      expect(nic1.name).to eq('eth1')
      expect(nic1.on_boot).to be(false)
      expect(nic1.boot_protocol).to eq(OvirtSDK4::BootProtocol::STATIC)
      expect(nic1.ip).not_to be_nil
      expect(nic1.ip.version).to eq(OvirtSDK4::IpVersion::V4)
      expect(nic1.ip.address).to eq('192.168.122.100')
      expect(nic1.ip.netmask).to eq('255.255.255.0')
      expect(nic1.ip.gateway).to eq('192.168.122.1')
    end
    proxy.update_cloud_init!(script)
  end

  it 'preserves the values that do not need special treatment' do
    script = <<~OPTIONS
      not_special_1: my_value_1
      host_name: my_host_name
      not_special_2: my_value_2
    OPTIONS
    expect(service).to receive(:update) do |vm|
      expected = <<~OPTIONS
        not_special_1: my_value_1
        not_special_2: my_value_2
      OPTIONS
      expect(vm.initialization.custom_script).to eq(expected)
    end
    proxy.update_cloud_init!(script)
  end

  it 'does not alter the custom script' do
    script = <<~OPTIONS
      #cloud-config
      write_files:
      - path: /tmp/test.txt
        content: |
          Here is a line.
          Another line is here.
        permissions: '0755'
    OPTIONS
    expect(service).to receive(:update) do |vm|
      expected = <<~OPTIONS
        write_files:
        - path: "/tmp/test.txt"
          content: |
            Here is a line.
            Another line is here.
          permissions: '0755'
      OPTIONS
      expect(vm.initialization.custom_script).to eq(expected)
    end
    proxy.update_cloud_init!(script)
  end

  it 'raises an exception when the script can not be parsed as a hash' do
    script = 'junk'
    expect { proxy.update_cloud_init!(script) }.to raise_error(/junk/)
  end
end
