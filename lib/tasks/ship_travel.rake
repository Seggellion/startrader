namespace :ship_travel do
  desc "Destroy stale unpaused ShipTravel rows and correct stranded in_transit ships"
  task cleanup_stale: :environment do
    current_tick = Tick.current
    cleaned_count = ShipTravel.cleanup_stale_after_arrival!(current_tick)
    Tick.instance.send(:correct_ship_statuses)

    puts "Destroyed #{cleaned_count} stale ShipTravel records at tick #{current_tick}."
  end
end
