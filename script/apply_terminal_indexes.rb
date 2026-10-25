# Standalone feature-only migrator: deliberately does not load Rails/initializers.
require "pg"
require "json"
require "optparse"
options = {}
OptionParser.new do |parser|
  parser.on("--database NAME") { |name| options[:database] = name }
  parser.on("--apply") { options[:apply] = true }
end.parse!
abort "An explicit expected database is required" unless options[:database]
connection = PG.connect(ENV.fetch("DATABASE_URL"),
  application_name: "startrader_terminal_feature_indexes",
  options: "-c lock_timeout=3000 -c statement_timeout=120000", connect_timeout: 10)
actual = connection.exec("SELECT current_database()").getvalue(0, 0)
abort "Database mismatch; no changes performed" unless actual == options[:database]
connection.exec("SET default_transaction_read_only = on") unless options[:apply]

indexes = [
  {version: "20261025010000", name: "index_terminals_on_unique_api_id", table: "terminals", column: "api_id", unique: true,
   sql: "CREATE UNIQUE INDEX CONCURRENTLY index_terminals_on_unique_api_id ON public.terminals (api_id) WHERE api_id IS NOT NULL"},
  {version: "20261025010100", name: "index_production_facilities_on_id_terminal", table: "production_facilities", column: "id_terminal", unique: false,
   sql: "CREATE INDEX CONCURRENTLY index_production_facilities_on_id_terminal ON public.production_facilities (id_terminal)"}
]
inspect_index = lambda do |index|
  connection.exec_params(<<~SQL, [index[:name]]).first
    SELECT i.indisvalid::text valid, i.indisready::text ready, i.indisunique::text is_unique,
      t.relname table_name, pg_get_indexdef(i.indexrelid) definition,
      array_to_string(ARRAY(SELECT a.attname FROM unnest(i.indkey) WITH ORDINALITY k(attnum,ord)
        JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=k.attnum ORDER BY k.ord),',') columns,
      pg_get_expr(i.indpred,i.indrelid) predicate
    FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_class t ON t.oid=i.indrelid
    WHERE n.nspname='public' AND c.relname=$1
  SQL
end
verify = lambda do |index, state|
  expected_predicate = index[:unique] ? "(api_id IS NOT NULL)" : nil
  unless state && state["valid"] == "true" && state["ready"] == "true" &&
      state["is_unique"] == index[:unique].to_s && state["table_name"] == index[:table] &&
      state["columns"] == index[:column] && state["predicate"] == expected_predicate
    abort "Index #{index[:name]} is incompatible/invalid; inspect and recover explicitly, never blindly retry"
  end
end
duplicate = connection.exec("SELECT api_id FROM public.terminals WHERE api_id IS NOT NULL GROUP BY api_id HAVING COUNT(*)>1 LIMIT 1").first
abort "Duplicate external identity; no data repair performed" if duplicate

report = {database: actual, mode: options[:apply] ? "apply" : "audit", indexes: []}
indexes.each do |index|
  state = inspect_index.call(index)
  verify.call(index, state) if state
  if options[:apply]
    connection.exec(index[:sql]) unless state
    state = inspect_index.call(index)
    verify.call(index, state)
    # Only the two reviewed feature versions. No unrestricted db:migrate.
    connection.exec_params("INSERT INTO public.schema_migrations(version) VALUES($1) ON CONFLICT DO NOTHING", [index[:version]])
  end
  report[:indexes] << {version: index[:version], name: index[:name], state: state}
end
puts JSON.pretty_generate(report)
connection.close
