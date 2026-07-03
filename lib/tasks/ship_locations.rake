namespace :ship_locations do
  desc "Backfill player current locations from known ship locations without guessing unknown ship locations"
  task backfill_player_locations: :environment do
    updated = 0
    skipped = 0

    ShardUser.includes(:user_ships).find_each do |shard_user|
      if shard_user.current_location_name.present?
        skipped += 1
        next
      end

      ship = shard_user.user_ships
                       .where.not(location_name: [nil, ""])
                       .order(updated_at: :desc)
                       .first
      location = Location.find_by(name: ship&.location_name)

      if location
        shard_user.update_current_location!(location)
        updated += 1
      else
        skipped += 1
      end
    end

    puts "Backfilled #{updated} shard user player locations; skipped #{skipped}."
  end
end
