describe :placeholders do
  include_examples :placeholders, ManageIQ::Providers::Ovirt::Engine.root.join('locale').to_s
end
