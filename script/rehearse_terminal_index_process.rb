# Strictly local qualification of the production standalone feature-only process.
require "pg"
require "open3"
require "rbconfig"
connection=PG.connect(ENV.fetch("DATABASE_URL"))
abort "Dedicated terminal test DB required" unless connection.exec("SELECT current_database()").getvalue(0,0)=="star_trader_terminal_test"
connection.exec("DROP INDEX CONCURRENTLY IF EXISTS public.index_terminals_on_unique_api_id")
connection.exec("DROP INDEX CONCURRENTLY IF EXISTS public.index_production_facilities_on_id_terminal")
connection.exec("DELETE FROM schema_migrations WHERE version IN ('20261025010000','20261025010100')")
connection.close
wrong,_,status=Open3.capture3(RbConfig.ruby,"script/apply_terminal_indexes.rb","--database","wrong_database","--apply")
raise "Mismatch was accepted" if status.success?
2.times do
  out,err,status=Open3.capture3(RbConfig.ruby,"script/apply_terminal_indexes.rb","--database","star_trader_terminal_test","--apply")
  raise "Feature process failed: #{err}" unless status.success?
  puts out
end
puts "Wrong DB refusal, explicit two-version application and idempotent verification passed"
