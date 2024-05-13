#
# This class is a responsible for managing a set of `OvirtSDK4::Connection` objects. Each connection is
# identified by the `id` attribute of the corresponding EMS, or by `nil` if there is no such EMS created yet.
#
# The connections will be created the first time that they are needed.
#
# Connections will be closed and created again if any of the options used to create them change.
#
# All the connections will be closed when the process finishes.
#
# Periodically the manager will obtain the identifiers of the EMSs from the database, and will automatically
# close the connections that correspond to identifiers that no longer exist.
#
class ManageIQ::Providers::Ovirt::ConnectionManager
  #
  # Returns the singleton instance.
  #
  def self.instance
    @instance ||= new
  end

  #
  # Creates a connection manager with an empty set of connections. This class is intended to be used as a
  # singleton, so use the `instance` class method instead.
  #
  # @api private
  #
  def initialize
    require 'ovirtsdk4'

    # This hash stores the connections that have already been created. The keys of the hash will be the
    # identifiers of the EMSs, and the values will be instances of the `Entry` class.
    @registry = {}

    # Load from the configuration the settings that control how often we purge connections that correspond to
    # EMSs that no longer exist:
    @purge_interval = settings.purge_interval.to_i_with_method
    @purge_time = Time.current

    # Make sure that all connections will be closed when the process finishes:
    at_exit do
      $rhevm_log.info("Closing all connections before exit.")
      clear
    end
  end

  #
  # Returns the connection that corresponds to the given EMS identifier and options. The connection
  # will be created if doesn't exist yet.
  #
  # If the connection already exists, but the given options are different to the options that were used to
  # create it, then it will be closed and created again. This is intended to support updates to the
  # credentials, for example changes of user names or passwords.
  #
  # @param id [Object] The id of the EMS.
  #
  # @param opts [Hash] The options that will be used to create the connection if it doesn't exist yet. The possible
  #   values are the same used in the constructor of the `OvirtSDK4::Connection` object.
  #
  # @return [OvirtSDK4::Connection] The connection that matches the given EMS id and options.
  #
  def get(id, opts)
    # Purge connections if needed:
    purge if purge?

    # Find the entry for the given id and return it if the options are compatible:
    entry = @registry[id]
    return entry.connection if entry && entry.compatible?(opts)

    # If there is an entry but it isn't compatible, then close and remove it:
    if entry
      $rhevm_log.info(
        "Existing connection for EMS with identifier '#{id}' and URL '#{entry.options[:url]}' isn't compatible " \
        "with the requested options, will close it and create a new one."
      )
      close(id)
    end

    # At this point we know that either there was no connection or else it needs to be created again:
    $rhevm_log.info("Creating new connection for EMS with identifier '#{id}' and URL '#{opts[:url]}'.")
    connection = OvirtSDK4::Connection.new(opts)
    entry = Entry.new(opts, connection)
    @registry[id] = entry

    # Return the new connection:
    connection
  end

  #
  # Closes the connection associated to the given EMS id.
  #
  # @param id [Object] The id of the EMS.
  #
  def close(id)
    entry = @registry.delete(id)
    return unless entry
    begin
      $rhevm_log.info("Closing connection for EMS with identifier '#{id}' and URL '#{entry.options[:url]}'.")
      entry.connection.close
    rescue OvirtSDK4::Error => error
      $rhevm_log.warn(
        "Error while closing connection for EMS with identifier '#{id}' and URL '#{entry.options[:url]}', " \
        "backtrace follows."
      )
      $rhevm_log.warn(error.message)
      error.backtrace.each do |line|
        $rhevm_log.warn(line)
      end
    end
  end

  #
  # Closes and forgets all the connections. Note that the manager can still be used, it will create the connections
  # again when needed.
  #
  def clear
    @registry.keys.each { |id| close(id) }
  end

  #
  # This class stores the information relative to a connection, like the options used to create it, and the connection
  # itself.
  #
  # This class is intended for internal use by other components of the SDK. Refrain from using it directly, as
  # backwards compatibility isn't guaranteed.
  #
  # @api private
  #
  class Entry
    #
    # Returns the options used to create the connection.
    #
    # @return [Hash]
    #
    attr_reader :options

    #
    # Returns the connection.
    #
    # @return [OvirtSDK4::Connection]
    #
    attr_reader :connection

    #
    # Creates a new object describing a connection.
    #
    # @param options [Hash] The options used to create the connection.
    # @param connection [OvirtSDK4::Connection] The connection itself.
    #
    def initialize(options, connection)
      @options = options
      @connection = connection
    end

    #
    # Checks if the this entry is compatible with the given options. A connection is compatible if it the options that
    # were used to create it are exactly the same than the given options.
    #
    def compatible?(opts)
      opts == @options
    end
  end

  private

  #
  # Checks if it is time to purge connections that correspond to EMSs that no longer exist in the database.
  #
  # @return [Boolean] `true` if it is time to purge, `false` otherwise.
  #
  # @api private
  #
  def purge?
    Time.current - @purge_time > @purge_interval
  end

  #
  # Closes all the connections that correspond that EMSs that no longer exist in the database.
  #
  # @api private
  #
  def purge
    # Get the identifiers of the EMS from the database and from the registry, and calculate the difference:
    database_ids = ManageIQ::Providers::Ovirt::InfraManager.pluck(:id)
    registry_ids = @registry.keys
    purged_ids = registry_ids - database_ids

    # Close the connections:
    purged_ids.each do |id|
      $rhevm_log.info(
        "The EMS with identifier '#{id}' no longer exists in the database, the connection will be closed."
      )
      close(id)
    end

    # Update the purge time:
    @purge_time = Time.current
  end

  #
  # Returns the settings of the connection manager.
  #
  # @return [Object] The `ems.ems_ovirt.connection_manager` branch of the settings.
  #
  # @api private
  #
  def settings
    ::Settings.ems.ems_ovirt.connection_manager
  end
end
