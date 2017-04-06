Vmdb::Gettext::Domains.add_domain(
  'ManageIQ_Providers_Ovirt',
  ManageIQ::Providers::Ovirt::Engine.root.join('locale').to_s,
  :po
)
