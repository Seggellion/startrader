require 'minitest/mock'
module TravelRepairFixtures
  def setup_travel_repair
    TravelResumeAction.delete_all
    StarBitizenRun.delete_all
    ShipTravel.delete_all
    UserShipCargo.delete_all
    UserShip.delete_all
    ShardUser.delete_all
    User.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all
    Commodity.delete_all
    Setting.delete_all
    Setting.create!(key:'secret_guid',value:'repair-secret',setting_type:'text')
    Setting.create!(key:'seconds_per_tick',value:'15',setting_type:'text')
    ShipTravel.delete_all
    TravelRequestReceipt.delete_all if defined?(TravelRequestReceipt)
    TravelArrivalEvent.delete_all if defined?(TravelArrivalEvent)
    Tick.delete_all
    MarketPriceUpdater.stub(:update_prices!,nil){Tick.create!(current_tick:100,sequence:101)}
    @origin=Location.create!(name:'Repair station',classification:'space_station',star_system_name:'Repair A')
    @gate=Location.create!(name:'Repair B Gateway (Repair A)',classification:'space_station',star_system_name:'Repair A')
    @destination=Location.create!(name:'Repair A Gateway (Repair B)',classification:'space_station',star_system_name:'Repair B')
    @user=User.create!(username:'RepairPilot',uid:SecureRandom.uuid,twitch_id:SecureRandom.uuid,user_type:'player')
    @shard=Shard.create!(name:'Repair Shard',region:'us',channel_uuid:SecureRandom.uuid)
    @player=ShardUser.create!(user:@user,shard:@shard,wallet_balance:10000,inventory:{'kept'=>7})
    @player.update_current_location!(@origin)
    @catalog_ship=Ship.create!(model:'Repair Hull',slug:'repair-hull',scu:20)
    @hull=UserShip.create!(user:@user,ship:@catalog_ship,shard:@shard,shard_user:@player,guid:SecureRandom.uuid,
      location_name:@origin.name,total_scu:20,used_scu:7,status:'docked')
    commodity=Commodity.create!(name:'Repair cargo')
    @cargo=UserShipCargo.create!(user_ship:@hull,commodity:commodity,commodity_name:commodity.name,scu:7,buy_price:12.34,sell_price:15.67)
  end
  def cleanup_travel_repair
    TravelResumeAction.delete_all
    ShipTravel.delete_all
    TravelArrivalEvent.delete_all
    TravelRequestReceipt.delete_all
    UserShipCargo.where(user_ship_id:@hull&.id).delete_all
    UserShip.where(id:@hull&.id).delete_all
    ShardUser.where(id:@player&.id).delete_all
    Shard.where(id:@shard&.id).delete_all
    User.where(id:@user&.id).delete_all
    Ship.where(id:@catalog_ship&.id).delete_all
    Location.where(id:[@origin&.id,@gate&.id,@destination&.id]).delete_all
    Commodity.where(name:'Repair cargo').delete_all
    Tick.delete_all
    Setting.delete_all
  end
  def gate_start(guid=SecureRandom.uuid)
    GateTravelService.new(ship_guid:@hull.guid,gateway_name:'Repair B Gateway',travel_guid:guid).call.travel
  end
  def saved_trip(ship=@hull, **attrs)
    ShipTravel.create!({user_ship:ship,from_location:@origin,to_location:@destination,travel_guid:SecureRandom.uuid,
      departure_tick:90,arrival_tick:100,total_duration_ticks:10,rabbitmq_environment:'dev'}.merge(attrs))
  end
  def assets
    [@hull.reload.attributes.slice('used_scu','total_scu'),@hull.user_ship_cargos.order(:id).map(&:attributes),
     @player.reload.attributes.slice('wallet_balance','inventory','currency')]
  end
end
