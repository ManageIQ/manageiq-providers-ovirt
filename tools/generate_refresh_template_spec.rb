describe(ManageIQ::Providers::Redhat::InfraManager::Refresh::Refresher) do
  ###
  # This is not a real spec, it is used to generate a template for a refresh spec
  # when we have a refresh that is known to work correctly and we need to test a
  # new one. So we first run this spec with the working refresh and it generates a new spec
  # file based on the template provided in the "filename" var and writes in to "output_file_name"
  ###
  before(:each) do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    @ems = FactoryBot.create(:ems_redhat, :zone => zone, :hostname => "localhost", :ipaddress => "localhost",
                              :port => 8443)
    @ems.update_authentication(:default => {:userid => "admin@internal", :password => "123456"})
    @ems.default_endpoint.verify_ssl = OpenSSL::SSL::VERIFY_NONE
    allow(@ems).to(receive(:supported_api_versions).and_return([3]))
    stub_settings_merge(:ems => { :ems_redhat => { :use_ovirt_engine_sdk => false } })
  end

  def relations_tree_to_a(expected_tree)
    h = {}
    return h if expected_tree.empty?
    expected_tree = sort_tree(expected_tree)
    expected_tree.each do |obj, children|
      key = [wrap_name_for_inspect(obj.class.name), obj.name]
      key << {:hidden => true} if obj.respond_to?(:hidden) && obj.hidden
      h[key] = relations_tree_to_a(children)
    end
    h
  end

  def wrap_name_for_inspect(name)
    InspectWrapper.new(name)
  end

  class InspectWrapper
    attr_reader :name
    def initialize(name)
      @name = name
    end

    def inspect
      name
    end
  end

  def sort_tree(tree)
    return tree if tree.blank?

    if tree.first.first.kind_of?(Array)
      # sorting expected tree
      tree.sort_by { |key, _children| [key[0].name,    key[1]] }
    else
      # sorting actual tree
      tree.sort_by { |obj, _children| [obj.class.name, obj.name] }
    end
  end

  def tree_a_to_s(tree_a)
    tree_s = tree_a.to_s
    tree_s.gsub!(/\]\s*?=>\s*?{\[/, "] => {\n[")
  end

  it("will generate a new cassete") do
    VCR.use_cassette("#{described_class.name.underscore}_generated_from_v3", :record => :new_episodes) do
      EmsRefresh.refresh(@ems)
    end
    @ems.reload
    # '/spec/models/manageiq/providers/redhat/infra_manager/refresh/refresher_spec_generator_template.txt')
    file_name = ManageIQ::Providers::Ovirt::Engine.root.join('<path to the template>')
    # '/spec/models/manageiq/providers/redhat/infra_manager/refresh/<insert_name_of_new_spec_here>_spec.rb')
    output_file_name = ManageIQ::Providers::Ovirt::Engine.root.join('<path to output>')

    text = File.read(file_name)

    new_contents = text.gsub(/>>>.*?<<</) do |s|
      exp = s.match(/>>>(.*)<<</)[1]
      if exp.start_with?("!~!")
        exp_inner = exp.match(/!~!(.*)$/)[1]
        eval(exp_inner)
        res = ''
      elsif exp.starts_with?("!~t~!")
        res = tree_a_to_s(relations_tree_to_a(@ems.descendants_arranged))
      else
        res = eval(exp)
        res = "nil" if res.nil?
      end
      res
    end
    new_contents.gsub!('"nil"', "nil")
    new_contents.gsub!('"true"', "true")
    File.open(output_file_name, "w") { |file| file.puts new_contents }
  end
end
