class RecordingModifier
  attr_accessor :yml

  def initialize(opts)
    @yml = Marshal.load(Marshal.dump(opts[:yml]))
  end

  def add_vm_with_inv
    @vm_adder ||= VmAdder.new(:yml => @yml)
    @vm_adder.add_with_inv
  end

  def add_template_with_inv
    @template_adder ||= TemplateAdder.new(:yml => @yml)
    @template_adder.add_with_inv
  end

  def add_host_with_inv
    @host_adder ||= HostAdder.new(:yml => @yml)
    @host_adder.add_with_inv
  end

  def add_cluster_with_inv
    @cluster_adder ||= ClusterAdder.new(:yml => @yml)
    @cluster_adder.add_with_inv
  end

  def add_vm_with_inv_and_cluster
    @vm_adder ||= VmAdder.new(:yml => @yml)
    @cluster_adder ||= ClusterAdder.new(:yml => @yml)
    cluster_uid = @cluster_adder.add_with_inv
    vm_uid = @vm_adder.add_with_inv(nil, nil, nil, @cluster_adder.orig_resource_uid => cluster_uid)
    { :new_vm_uid => vm_uid, :new_cluster_uid => cluster_uid }
  end

  def add_vm_to_cluster(cluster_uid)
    @vm_adder ||= VmAdder.new(:yml => @yml)
    @vm_adder.add_with_inv(nil, nil, nil, ClusterAdder::ORIG_RESOURCE_ID => cluster_uid)
  end

  def add_host_to_cluster(cluster_uid)
    @host_adder ||= HostAdder.new(:yml => @yml)
    @host_adder.add_with_inv(nil, nil, nil, ClusterAdder::ORIG_RESOURCE_ID => cluster_uid)
  end

  class BaseAdder
    attr_accessor :yml

    def initialize(opts)
      @yml = opts[:yml]
    end

    def inv_types
      []
    end

    def duplicate_by_key(key_str, uid, new_uid = nil)
      new_uid ||= SecureRandom.uuid
      new_key = key_str.gsub(uid, new_uid)
      yml[new_key] = Marshal.load(Marshal.dump(yml[key_str]))
      yml[new_key][0][:body].gsub!(uid, new_uid)
      new_uid
    end

    def add_with_inv(orig_uid = nil, orig_name = nil, new_resource_uid = nil, substitution_hash = {})
      orig_uid ||= orig_resource_uid
      orig_name ||= orig_resource_name
      new_resource_uid ||= SecureRandom.uuid
      substitution_hash = { orig_uid => new_resource_uid, orig_name => new_resource_uid }.merge(substitution_hash)
      new_resource_uid = add_resource_xml_node(new_resource_uid, substitution_hash)
      inv_types.each do |inv_type|
        duplicate_invs(inv_type, orig_uid, new_resource_uid)
      end
      new_resource_uid
    end

    def add_resource_xml_node(new_resource_uid, substitution_hash)
      resource_xml_str = resource_xml_memoized.to_s
      substitution_hash.each do |key, val|
        resource_xml_str.gsub!(key, val)
      end
      resources_xml = current_resources_xml
      resources_xml.root.first_element_child.after(resource_xml_str)
      set_resources_xml(resources_xml)
      new_resource_uid
    end

    def set_resources_xml(xml_str)
      yml["#{resource_key_prefix}{}GET"][0][:body] = xml_str.to_s
    end

    def current_resources_xml
      resources_arr = yml["#{resource_key_prefix}{}GET"]
      Nokogiri::XML(resources_arr[0][:body])
    end

    def resource_xml_memoized
      @resource_xml ||= begin
                    doc = current_resources_xml
                    doc.at(resource_type_name)
                  end
    end

    def resource_type_name
      raise(NotImplementedError, 'abstract')
    end

    def orig_resource_uid
      raise(NotImplementedError, 'abstract')
    end

    def orig_resource_name
      raise(NotImplementedError, 'abstract')
    end

    def resource_key_prefix
      raise(NotImplementedError, 'abstract')
    end

    def duplicate_invs(inv_name, existing_vm_uid, new_vm_uid)
      key = "#{resource_key_prefix}/#{existing_vm_uid}/#{inv_name}{}GET"
      duplicate_by_key(key, existing_vm_uid, new_vm_uid)
    end
  end

  class VmAdder < BaseAdder
    def orig_resource_uid
      "0d37ca3b-cdbc-4b78-b0b9-7cd71ddc7e35"
    end

    def orig_resource_name
      "my-cirros-vm"
    end

    def inv_types
      %w(reporteddevices nics snapshots diskattachments)
    end

    def resource_key_prefix
      "https://pluto-vdsg.eng.lab.tlv.redhat.com:443/ovirt-engine/api/vms"
    end

    def resource_type_name
      "vm"
    end
  end

  class HostAdder < BaseAdder
    def resource_type_name
      "host"
    end

    def orig_resource_uid
      "265e8f1a-1115-47d1-a55a-c84913e37e3e"
    end

    def orig_resource_name
      "bodh1"
    end

    def resource_key_prefix
      "https://pluto-vdsg.eng.lab.tlv.redhat.com:443/ovirt-engine/api/hosts"
    end

    def inv_types
      %w(nics statistics)
    end
  end

  class TemplateAdder < BaseAdder
    def resource_type_name
      "template"
    end

    def orig_resource_uid
      "88204489-0ba8-4f1a-8e2d-e7f75835b8df"
    end

    def orig_resource_name
      "cirros-0.4"
    end

    def resource_key_prefix
      "https://pluto-vdsg.eng.lab.tlv.redhat.com:443/ovirt-engine/api/templates"
    end

    def inv_types
      ["diskattachments"]
    end
  end

  class ClusterAdder < BaseAdder
    ORIG_RESOURCE_ID = "5a55d518-00c7-00ef-015b-000000000055".freeze
    def resource_type_name
      "cluster"
    end

    def orig_resource_uid
      self.class::ORIG_RESOURCE_ID
    end

    def orig_resource_name
      "Default"
    end

    def resource_key_prefix
      "https://pluto-vdsg.eng.lab.tlv.redhat.com:443/ovirt-engine/api/clusters"
    end

    def inv_types
      []
    end
  end
end
