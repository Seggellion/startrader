# app/controllers/api/ship_travel_controller.rb
module Api
  class ShipTravelController < ApplicationController
    # API endpoint: skip CSRF
    skip_before_action :verify_authenticity_token

    # POST /api/travel
    def create

      permitted_params = travel_params

      if permitted_params[:travel_guid].blank?
        return render json: { error: "travel_guid is required." }, status: :unprocessable_entity
      end

      user        = find_or_create_user_by_guid_or_name(permitted_params[:player_guid], permitted_params[:player_name])
      shard       = resolve_shard(permitted_params[:shard_uuid])
      #ship        = resolve_ship(travel_params[:ship_guid], travel_params[:ship_slug])
      destination = resolve_location_by_name(permitted_params[:to_location])

      return render json: { error: "Location not found." }, status: :not_found if destination.nil?

    user_ship = resolve_user_ship_by_guid_or_slug(
      user:        user,
      shard:       shard,
      ship_guid:   permitted_params[:ship_guid],
      ship_slug:   permitted_params[:ship_slug]
    )

     # user_ship = find_or_create_user_ship(user, ship, shard)

      # If caller provided a from_location, ensure the server knows it (helpful for first-time players)
      if permitted_params[:from_location].present?
        from_loc = resolve_location_by_name(permitted_params[:from_location])
        user_ship.update(location: from_loc) if from_loc && user_ship.location.nil?
      end

      # Backfill a starting location if still nil (defaults to star system’s planet to keep things valid)
      if user_ship.location.nil?
        fallback = Location.planets.find_by(name: destination.star_system_name) # e.g., "Stanton"
        user_ship.update(location: fallback) if fallback
      end

      # --- NEW: Prevent traveling to the current location ---
      if user_ship.location_name == destination.name
        return render json: { error: "You are already docked at #{destination.name}." }, status: :unprocessable_entity
      end
      # -----------------------------------------------------

      # Star system travel restriction
      if user_ship.location && destination.star_system_name != user_ship.location.star_system_name
        return render json: { error: "You cannot travel outside your current star system." }, status: :unprocessable_entity
      end

      Rails.logger.info "=== TRANSIT DEBUG START ==="
      Rails.logger.info "Current Server Tick: #{Tick.current}"
      
      existing_travel = ShipTravel.where(user_ship_id: user_ship.id, is_paused: false, completed_at_tick: nil).last
      if existing_travel
        Rails.logger.info "Found existing travel ID: #{existing_travel.id}"
        Rails.logger.info "Existing Travel Arrival Tick: #{existing_travel.arrival_tick}"
        Rails.logger.info "Is Arrival >= Current Tick? #{existing_travel.arrival_tick >= Tick.current}"
      else
        Rails.logger.info "No active travel records found for this ship."
      end
      Rails.logger.info "=== TRANSIT DEBUG END ==="

      # Prevent double booking the same ship
      if ShipTravel.where(user_ship_id: user_ship.id, is_paused: false, completed_at_tick: nil)
                  .where('arrival_tick >= ?', Tick.current)
                  .exists?
                  
        return render json: { error: "Ship is already in transit." }, status: :unprocessable_entity
      end

      travel = TravelService.new(
        user_ship: user_ship,
        to_location: destination,
        travel_guid: permitted_params[:travel_guid]
      ).call
      render json: {
        status:        "travel_started",
        channel_name: shard.name,
        user_ship_id:  user_ship.id,
        travel_guid:   travel.travel_guid,
        destination:   destination.name,
        current_tick:  Tick.current,
        arrival_tick:  travel.arrival_tick,
        time_remaining: travel&.seconds_remaining(Tick.current)
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # GET /api/location/:user_ship_id
    def location
      user_ship = UserShip.find_by(id: params[:user_ship_id])
      return render json: { error: "User ship not found." }, status: :not_found if user_ship.nil?

      process_due_arrival_for(user_ship)
      user_ship.reload

      active_travel = user_ship.active_travel

      if active_travel
        phase = active_travel.current_interdictable_phase(Tick.current)
        render json: {
          in_transit:     true,
          travel_guid:    active_travel.travel_guid,
          from_location:  active_travel.from_location.name,
          to_location:    active_travel.to_location.name,
          departure_tick: active_travel.departure_tick,
          arrival_tick:   active_travel.arrival_tick,
          current_tick:   Tick.current,
          progress:       active_travel.progress_fraction(Tick.current),  # 0.0..1.0
          interdictable:  !active_travel.is_paused && !phase.nil?,
          interdict_phase: phase,  # null, "departure" or "arrival"
          windows: {
            departure: active_travel.departure_window_range.to_a.minmax,
            arrival:   active_travel.arrival_window_range.to_a.minmax
          }
        }
      else
        # optionally expose paused status
        paused = user_ship.ship_travels.where(is_paused: true).order(updated_at: :desc).first
        if paused
          render json: {
            in_transit: false,
            paused: true,
            travel_guid: paused.travel_guid,
            paused_at_tick: paused.paused_at_tick,
            remaining_ticks_from_arrival: paused.remaining_ticks_from_arrival,
            from_location: paused.from_location.name,
            to_location: paused.to_location.name
          }
        else
          completed = latest_completed_travel_for(user_ship)

          if completed
            render json: {
              in_transit: false,
              arrived: true,
              location: user_ship.location&.name || completed.to_location.name,
              travel_guid: completed.travel_guid
            }
          else
            render json: { in_transit: false, location: user_ship.location&.name || "Unknown" }
          end
        end
      end



    end

      def interdict_by_guid        
        
      user_ship = UserShip.find_by!(guid: params[:guid])
      travel = user_ship.active_travel
      return render json: { error: "No active travel for this ship." }, status: :unprocessable_entity if travel.nil?

      phase = travel.current_interdictable_phase(Tick.current)
      return render json: { error: "Not in an interdictable window." }, status: :unprocessable_entity if phase.nil?

      travel.interdict!(Tick.current)
      user_ship.update!(status: "interdicted")

      render json: {
        status: "interdicted",
        user_ship_guid: user_ship.guid,
        ship_travel_id: travel.id,
        travel_guid: travel.travel_guid,
        phase: phase,
        paused_at_tick: travel.paused_at_tick,
        remaining_ticks_from_arrival: travel.remaining_ticks_from_arrival,
        user_ship_cargo: TradeService.user_ship_cargo_json(user_ship)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "User ship not found." }, status: :not_found
    end

    # --- NEW: Resume by user_ship.guid ---
    # POST /api/user_ships/:guid/resume
    def resume_by_guid
      user_ship = UserShip.find_by!(guid: params[:guid])

    travel = user_ship.ship_travel
    return render json: { error: "No paused travel for this ship." }, status: :unprocessable_entity if travel.nil? || !travel.is_paused?

      travel.resume!(Tick.current)
      user_ship.update!(status: "in_transit")

      render json: {
        status: "resumed",
        user_ship_guid: user_ship.guid,
        ship_travel_id: travel.id,
        travel_guid: travel.travel_guid,
        departure_tick: travel.departure_tick,
        arrival_tick: travel.arrival_tick,
        remaining_duration: travel.total_duration_ticks
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "User ship not found." }, status: :not_found
    end


    # POST /api/ship_travel/:id/interdict
    def interdict
      travel = ShipTravel.find(params[:id])
      phase = travel.current_interdictable_phase(Tick.current)
      return render json: { error: "Not in an interdictable window." }, status: :unprocessable_entity if phase.nil?

      travel.interdict!(Tick.current)
      travel.user_ship.update!(status: "interdicted")

      render json: {
        status: "interdicted",
        travel_guid: travel.travel_guid,
        phase: phase,
        paused_at_tick: travel.paused_at_tick,
        remaining_ticks_from_arrival: travel.remaining_ticks_from_arrival,
        user_ship_cargo: TradeService.user_ship_cargo_json(travel.user_ship)
      }
    end

   def interdictable_index
      tick   = Tick.current
      limit  = params[:limit].presence&.to_i || 100
      offset = params[:offset].presence&.to_i || 0

      scope = ShipTravel
                .interdictable_now_sql(tick)
                .includes(:from_location, :to_location, user_ship: [:ship, :user, :shard])
                .order(:arrival_tick)

      if params[:shard_uuid].present?
        shard = resolve_shard(params[:shard_uuid])
        scope = scope.for_shard(shard.name)
      end
      if params[:star_system_name].present?
        scope = scope.for_star_system(params[:star_system_name])
      end

      ships = scope.limit(limit).offset(offset).map do |st|
        phase = st.current_interdictable_phase(tick) # cheap to compute for labeling
        serialize_interdictable(st, phase, tick)
      end

      render json: { current_tick: tick, count: ships.size, ships: ships }
    end
  

  # POST /api/ship_travel/:id/resume
  def resume
  
    ship = UserShip.find_by(guid:params[:id])
    travel = ship.ship_travel
    travel.resume!(Tick.current)
    travel.user_ship.update!(status: "in_transit")

    render json: {
      status: "resumed",
      travel_guid: travel.travel_guid,
      departure_tick: travel.departure_tick,
      arrival_tick: travel.arrival_tick,
      remaining_duration: travel.total_duration_ticks
    }
  end


    # DELETE /api/cancel
    # Accepts either legacy params (username, shard) or new ones (player_guid/player_name, shard_uuid)
    def destroy
      
      user  = if params[:player_guid].present?
                User.find_by(uid: params[:player_guid]) || User.where("LOWER(username) = ?", params[:player_name].to_s.downcase.strip).first
              else
                User.where("LOWER(username) = ?", params[:username].to_s.downcase.strip).first
              end
      return render json: { error: "User not found." }, status: :not_found if user.nil?

      shard = if params[:shard_uuid].present?
                Shard.find_by(channel_uuid: params[:shard_uuid])
              else
                # Allow legacy destroy with a shard name
                Shard.where("LOWER(name) = ?", params[:shard].to_s.downcase).first
              end
      return render json: { error: "Shard not found." }, status: :not_found if shard.nil?

      shard_user = user.shard_users.find_by("shard_id = ? OR shard_name ILIKE ?", shard.id, shard.name)
      return render json: { error: "User not associated with shard." }, status: :not_found if shard_user.nil?

      user_ship = shard_user.user_ships.order(updated_at: :desc).first
      return render json: { error: "User ship not found or does not belong to the specified user." }, status: :not_found if user_ship.nil?

      if (active_travel = user_ship.active_travel).present?
        active_travel.destroy
        user_ship.update(status: "Floating aimlessly in space")
      end

      render json: { status: "travel_cancelled", user_ship_id: user_ship.id }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

      def serialize_interdictable(st, phase, tick)
        {
          travel_guid:    st.travel_guid,
          ship_guid:   st.user_ship.guid,
          ship_model:     st.user_ship.ship.model,
          player_name:    st.user_ship.user.username,
          shard_name:     st.user_ship.shard_name,
          shard_uuid:     st.user_ship.shard&.channel_uuid,
          from_location:  st.from_location.name,
          to_location:    st.to_location.name,
          phase:          phase,
          departure_tick: st.departure_tick,
          arrival_tick:   st.arrival_tick,
          total_duration: st.duration_ticks,
          windows: {
            departure: st.departure_window_range.to_a.minmax,
            arrival:   st.arrival_window_range.to_a.minmax
          },
          ticks_to_arrival: st.distance_from_arrival_in_ticks(tick),
          progress:         st.progress_fraction(tick)       # 0.0..1.0
        }
      end
      
    def travel_params
      # New payload shape
      params.require(:ship_travel).permit(
        :ship_guid,
        :travel_guid,
        :ship_slug,
        :player_guid,
        :player_name,
        :to_location,
        :from_location,
        :shard_uuid
      )
    end

    def process_due_arrival_for(user_ship)
      travel = user_ship.ship_travels
                        .where(is_paused: false, completed_at_tick: nil)
                        .where.not(arrival_tick: 0)
                        .where("arrival_tick <= ?", Tick.current)
                        .order(arrival_tick: :desc, updated_at: :desc)
                        .first

      ShipTravelArrivalProcessor.new(travel: travel, current_tick: Tick.current).call if travel
    end

    def latest_completed_travel_for(user_ship)
      user_ship.ship_travels
               .completed
               .where(to_location: user_ship.location)
               .order(completed_at_tick: :desc, updated_at: :desc)
               .first
    end

    def find_or_create_user_by_guid_or_name(player_guid, player_name)
      normalized_name = player_name.to_s.downcase.strip

      # Prefer GUID if provided; store Twitch as provider to match your data model
      user = if player_guid.present?
               User.find_by(uid: player_guid)
             end

      user ||= User.where("LOWER(username) = ?", normalized_name).first

      unless user
        user = User.create!(
          username:   normalized_name.presence || "pilot_#{SecureRandom.hex(4)}",
          uid:        player_guid.presence || SecureRandom.hex(10),
          twitch_id:  SecureRandom.hex(10),
          user_type:  "player",
          provider:   "twitch"
        )
      end

      user
    end

    def resolve_shard(shard_uuid)
      raise ArgumentError, "Missing shard UUID." if shard_uuid.blank?

      shard = Shard.find_by(channel_uuid: shard_uuid)
      raise ActiveRecord::RecordNotFound, "Shard not found." if shard.nil?

      shard
    end

   def resolve_user_ship_by_guid_or_slug(user:, shard:, ship_guid:, ship_slug:)
  # If a shard is provided, ensure a ShardUser exists (create if missing)
  shard_user =
    if shard.present?
      # Prefer scoping through associations if available; otherwise fallback to the model
      (user.respond_to?(:shard_users) ? user.shard_users : ShardUser)
        .find_or_create_by!(user_id: user.id, shard_id: shard.id) do |su|
          # Add any default attributes for new ShardUser here (e.g., wallet_balance)
          su.shard_name = shard.name if su.respond_to?(:shard_name)
        end
    else
      nil
    end

  # 1) Try to find an existing hull by GUID
  if ship_guid.present?
    if (existing = user.user_ships.find_by(guid: ship_guid))
      # Keep shard attribution consistent
      if shard.present?
        changes = {}
        changes[:shard_id]      = shard.id      if existing.shard_id      != shard.id
        changes[:shard_name]    = shard.name    if existing.respond_to?(:shard_name) && existing.shard_name != shard.name
        changes[:shard_user_id] = shard_user.id if existing.respond_to?(:shard_user_id) && existing.shard_user_id != shard_user&.id
        existing.update!(changes) unless changes.empty?
      end
      return existing
    end
  end

  # 2) No existing hull; we must have a slug to create from the catalog
  raise ActiveRecord::RecordInvalid, "ship_slug is required when ship_guid not found." if ship_slug.blank?

  ship = Ship.find_by(slug: ship_slug)

  raise ActiveRecord::RecordNotFound, "Ship not found for slug #{ship_slug.inspect}." if ship.nil?

  # 3) Create a new UserShip derived from the catalog row
  ActiveRecord::Base.transaction do
    user.user_ships.create!(
      guid:          ship_guid.presence || SecureRandom.uuid,
      ship:          ship,
      ship_slug:     ship.slug,
      total_scu:     ship.scu,
      used_scu:      0,
      shard_id:      shard&.id,
      shard_name:    (shard&.name if UserShip.attribute_names.include?("shard_name")),
      shard_user_id: (shard_user&.id if UserShip.attribute_names.include?("shard_user_id")),
      status:        "docked"
    )
  end
end


def resolve_location_by_name(name)
  LocationResolver.resolve(name)
end

    # Ensure a UserShip exists on this shard for the chosen hull
    def find_or_create_user_ship(user, ship, shard)
      user.user_ships.find_or_create_by!(ship: ship, shard_id: shard.id) do |user_ship|
        user_ship.total_scu  = ship.scu
        user_ship.used_scu   = 0
        user_ship.location   = nil # set by from_location or fallback above
        user_ship.status     = "Idle"
      end
    end
  end
end
