#!/usr/bin/env ruby

# This script removes duplicate block storages that were created due to changing the way
# storage "location" is calculated.
# It copies the tags from the old storages and then removes them from ManageIQ.
# See https://github.com/ManageIQ/manageiq-providers-ovirt/pull/387
# And https://bugzilla.redhat.com/show_bug.cgi?id=1697467
# Recommended usage: run with -dv argument to have a dry run with output.
# If it makes sense, run with -v

class HandleStorageDuplication
  attr_reader :ems, :dry_run, :verbose
  def initialize(opts)
    @ems = opts[:ext_management_system]
    @dry_run = opts[:dry_run]
    @verbose = opts[:verbose]
  end

  def affected_storages
    @affected_storages ||= @ems ? @ems.storages.where.not(:store_type => ["NFS", "GLANCE"]) : Storage.where.not(:store_type => ["NFS", "GLANCE"])
  end

  def handle_duplicates
    affected_storages.each do |storage|
      next if belongs_to_non_rhv_povider?(storage)

      old_st_location = old_storage_location(storage)
      next if old_st_location == storage.location

      old_storage = Storage.where(:location => old_st_location).first
      merge_old_storage(storage, old_storage) if old_storage
    end
  end

  def belongs_to_non_rhv_povider?(storage)
    storage.ext_management_system && !storage.ext_management_system.kind_of?(ManageIQ::Providers::Ovirt::InfraManager)
  end

  def old_storage_location(storage)
    ext_management_systems = storage.ext_management_system ? [storage.ext_management_system] : ManageIQ::Providers::Ovirt::InfraManager.all
    storagedomain = nil
    ext_management_systems.detect do |ems|
      storage_id = storage.ems_ref.split("/").last
      storagedomain = ems.with_provider_connection do |conn|
        conn.system_service.storage_domains_service.storage_domain_service(storage_id).get
      rescue
        puts "tried to detect storage with id: #{storage_id} in #{ems.name}" if verbose
        nil
      end
    end
    return nil unless storagedomain

    logical_units = storagedomain.dig(:storage, :volume_group, :logical_units)
    logical_unit =  logical_units&.first
    logical_unit&.id
  end

  def merge_old_storage(storage, old_storage)
    will_or_would = dry_run ? "Would have been deleted" : "Will be deleted"
    if verbose
      puts "The storage #{old_storage.name}, with id: #{old_storage.id} and location #{old_storage.location}"\
        "#{will_or_would} and its tags moved to: #{storage.name}, with id: #{storage.id} and location #{storage.location}"
    end
    return if dry_run

    transfer_tags(storage, old_storage)
    old_storage.reload.destroy
  end

  def transfer_tags(storage, old_storage)
    old_taggings = old_storage.taggings
    old_taggings.each do |old_tagging|
      old_tagging.update_column(:taggable_id, storage.id)
    end
  end
end

require 'optimist'

opts = Optimist.options(ARGV) do
  banner "This will delete duplicate rhv storages created by changing the way we get set the storage location from your database\n" \
    "See https://github.com/ManageIQ/manageiq-providers-ovirt/pull/387\n" \
    "And https://bugzilla.redhat.com/show_bug.cgi?id=1697467"

  opt :dry_run,  "Dry Run, do not make any real db changes. Use it with the verbose option to see the changes", :short => "d"
  opt :verbose,  "Print out which storages are being removed", :short => "v"
end

HandleStorageDuplication.new(:dry_run => opts[:dry_run], :verbose => opts[:verbose]).handle_duplicates
