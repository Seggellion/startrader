# Synthetic local scale qualification; never run against production.
ENV["RAILS_ENV"] = "test"
ENV["TICK_BOOTSTRAP"] = "false"
require_relative "../config/environment"
require_relative "../test/support/no_real_broker"
require "json";require "benchmark";require "etc"
connection=ActiveRecord::Base.connection
raise "Dedicated scale DB required" unless connection.select_value("SELECT current_database()") == "star_trader_terminal_scale"
report={machine:{ruby:RUBY_DESCRIPTION,cpu_count:Etc.nprocessors,platform:RUBY_PLATFORM},scales:[]}
[1,10,100].each do |factor|
  ProductionFacility.delete_all;Terminal.delete_all;Commodity.delete_all;Location.delete_all
  host=Location.create!(name:"Scale Host",star_system_name:"Stanton",planet_name:"Scale Planet",classification:"city")
  Commodity.create!(name:"Scale Ore")
  now=Time.current
  (0...(830*factor)).each_slice(1000) do |range|
    Terminal.insert_all!(range.map{|n|{api_id:n+1,name:(n<2 ? "Duplicate context terminal" : "Scale terminal #{n}"),code:"CODE#{n}",nickname:"Scale alias #{n}",location_name:host.name,created_at:now,updated_at:now}})
  end
  eligible=135*factor
  (0...(2590*factor)).each_slice(1000) do |range|
    ProductionFacility.insert_all!(range.map do |n|
      terminal_id=n<101*factor ? 1 : 2+(n%(eligible-1))
      {api_id:n+1,id_terminal:terminal_id,commodity_name:"Scale Ore",facility_name:"Scale terminal #{terminal_id}",terminal_name:"Scale terminal #{terminal_id}",location_name:host.name,
       price_buy:12.34,price_sell:23.45,production_rate:0,consumption_rate:0,inventory:10,max_inventory:100,
       created_at:now,updated_at:now}
    end)
  end
  connection.execute("ANALYZE terminals");connection.execute("ANALYZE production_facilities")
  samples=[];allocations=[];queries=[]
  5.times do
    statements=[]
    subscriber=->(_name,_start,_finish,_id,payload) { statements<<payload[:sql] unless payload[:name]=="SCHEMA" || payload[:cached] || payload[:sql].match?(/\A(?:BEGIN|COMMIT|SET |SAVEPOINT|RELEASE)/) }
    before=GC.stat(:total_allocated_objects)
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber,"sql.active_record") do
        samples << Benchmark.realtime { r=MarketQuery.new(terminal_api_id:"1").call;raise "DOM bound" if r.buy.rows.size+r.sell.rows.size>100; (r.buy.rows+r.sell.rows).each{|row|row.location;row.commodity} }*1000
      end
    end
    allocations<<GC.stat(:total_allocated_objects)-before
    queries<<statements.size
  end
  searches={}
  {"substring"=>{q:"Scale"},"no_match"=>{q:"missinglongword"},"system"=>{q:"Scale",star_system:"Stanton"},"duplicate_context"=>{q:"Duplicate context"}}.each do |key,input|
    times=[];bytes=[];count=[]
    5.times do
      times<<Benchmark.realtime { value=TerminalSearchQuery.new(input).call;bytes<<value.to_json.bytesize;count<<value[:results].size }*1000
    end
    searches[key]={max_ms:times.max,median_ms:times.sort[2],max_bytes:bytes.max,max_options:count.max}
    raise "Lookup bound" if bytes.max>20480 || count.max>20
  end
  plans={}
  {"worst_terminal"=>"SELECT id FROM production_facilities WHERE id_terminal=1 ORDER BY updated_at DESC NULLS LAST,id LIMIT 50",
   "substring"=>"SELECT api_id FROM terminals WHERE name ILIKE '%Scale%' ORDER BY name,api_id LIMIT 21",
   "no_match"=>"SELECT api_id FROM terminals WHERE name ILIKE '%missinglongword%' LIMIT 21"}.each do |key,sql|
    plan=JSON.parse(connection.select_value("EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) #{sql}")).first
    nodes=[];walk=->(node){nodes<<node.slice("Node Type","Relation Name","Index Name","Actual Rows","Actual Loops","Rows Removed by Filter");(node["Plans"]||[]).each{|child|walk.call(child)}}
    walk.call(plan["Plan"])
    plans[key]={execution_ms:plan["Execution Time"],planning_ms:plan["Planning Time"],shared_hits:plan["Plan"]["Shared Hit Blocks"],nodes:nodes}
  end
  report[:scales]<<{factor:factor,terminals:Terminal.count,offers:ProductionFacility.count,
    grouped_query_ms:samples,data_statements:queries,max_allocations:allocations.max,lookup:searches,plans:plans}
  puts "Qualified synthetic #{factor}x: #{Terminal.count} terminals / #{ProductionFacility.count} offers; #{queries.max} data statements"
  raise "Query budget" if queries.max>8
end
File.write("docs/STARTRADER_TERMINAL_FILTER_SCALE.json",JSON.pretty_generate(report))
puts "Scale results saved"
