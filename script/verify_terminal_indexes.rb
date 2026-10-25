# Local qualification only. Never run this destructive index rehearsal on production.
ENV["RAILS_ENV"] = "test"
ENV["TICK_BOOTSTRAP"] = "false"
require_relative "../config/environment"
require_relative "../test/support/no_real_broker"
require_relative "../db/migrate/20261025010000_index_terminal_external_identity"
require_relative "../db/migrate/20261025010100_index_facilities_by_terminal"
connection = ActiveRecord::Base.connection
raise "Dedicated terminal test DB required" unless connection.select_value("SELECT current_database()") == "star_trader_terminal_test"
raise "Unexpected active transaction" if connection.transaction_open?
migration = IndexTerminalExternalIdentity.new
begin
  migration.down
  Terminal.insert_all!([
    {api_id: 2_100_000_001, name: "Index rehearsal one", created_at: Time.current, updated_at: Time.current},
    {api_id: 2_100_000_001, name: "Index rehearsal two", created_at: Time.current, updated_at: Time.current}
  ])
  begin
    migration.up
    raise "Duplicate audit did not reject"
  rescue ActiveRecord::MigrationError => error
    raise unless error.message.include?("Duplicate terminal")
    puts "Duplicate identity audit rejects without deduplicating"
  end
ensure
  Terminal.where(api_id: 2_100_000_001).delete_all
  migration.up unless connection.index_exists?(:terminals, :api_id, name: IndexTerminalExternalIdentity::NAME)
end
IndexFacilitiesByTerminal.new.down
IndexFacilitiesByTerminal.new.up
valid = connection.select_rows("SELECT c.relname,i.indisvalid,i.indisready FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE c.relname IN ('index_terminals_on_unique_api_id','index_production_facilities_on_id_terminal')")
raise "Indexes not ready" unless valid.size == 2 && valid.all? { |_, valid, ready| valid && ready }
puts "Concurrent down/up rehearsal and valid/ready indexes passed"
