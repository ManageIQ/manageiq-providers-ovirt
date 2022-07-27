FactoryBot.define do
  factory :storage_ovirt, :parent => :storage_nfs do
    sequence(:ems_ref)             { |n| "/api/storagedomains/#{n}" }
    sequence(:storage_domain_type) { |n| n == 2 ? "iso" : "data" }
  end
end
