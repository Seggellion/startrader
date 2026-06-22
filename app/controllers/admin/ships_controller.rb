# app/controllers/admin/ships_controller.rb
module Admin
  class ShipsController < ApplicationController
    before_action :set_ship, only: [:edit, :update, :destroy, :update_category]

    SHIP_PARAM_KEYS = %i[
      model manufacturer_id scu crew length beam height msrp year_introduced
      ship_image_primary ship_image_secondary image_topdown hyd_fuel_capacity
      qnt_fuel_capacity liquid_storage_capacity mass vehicle_type career role
      size hp speed afterburner_speed ifcs_pitch_max ifcs_yaw_max ifcs_roll_max
      shield_face_type armor_physical_dmg_reduction armor_energy_dmg_reduction
      armor_distortion_dmg_reduction armor_em_signal_reduction
      armor_ir_signal_reduction armor_cs_signal_reduction capacitor_crew_load
      capacitor_crew_regen capacitor_turret_load capacitor_turret_regen
      alt_ship_name component_size api_id id_company id_parent
      ids_vehicles_loaners name_full slug uuid crew_range container_sizes
      pad_type game_version is_addon is_boarding is_bomber is_cargo is_carrier
      is_civilian is_concept is_construction is_datarunner is_docking is_emp
      is_exploration is_ground_vehicle is_hangar is_industrial is_interdiction
      is_loading_dock is_medical is_military is_mining is_passenger is_qed
      is_racing is_refinery is_refuel is_repair is_research is_salvage
      is_scanning is_science is_showdown_winner is_spaceship is_starter
      is_stealth is_tractor_beam is_quantum_capable url_store url_brochure
      url_hotsite url_video url_photos date_added date_modified company_name
      name width fuel_quantum fuel_hydrogen
    ].freeze

    def index
      @ships = Ship.order(created_at: :desc)
    end

    def new
      @ship = Ship.new
    end

    def create
      @ship = Ship.new(ship_params)

      if @ship.save
        redirect_to edit_admin_ship_path(@ship), notice: 'Ship was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def import_starbitizen
      begin
        result = Admin::Data::StarbitizenShipImporter.import_raw_json!(params[:json_data])
        flash_key = result.failed_count.positive? ? :alert : :notice

        redirect_to admin_ships_path, flash_key => result.message
      rescue JSON::ParserError
        redirect_to admin_ships_path, alert: "Invalid JSON format. Please ensure you pasted valid JSON."
      rescue => e
        redirect_to admin_ships_path, alert: "An error occurred: #{e.message}"
      end
    end

    def update
      if @ship.update(ship_params)
        redirect_to edit_admin_ship_path(@ship), notice: 'Ship was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def update_category
      if @ship.update(ship_params.slice(:category_id))
        render json: { success: true }
      else
        render json: { success: false }, status: :unprocessable_entity
      end
    end

    def delete_all
      Ship.destroy_all
      redirect_to admin_ships_path, notice: 'All ships have been deleted successfully.'
    end

    def destroy
      @ship.destroy
      redirect_to admin_ships_path, notice: 'Ship was successfully deleted.'
    end

    private

    def set_ship
      
      @ship = Ship.find(params[:id])
    end


    def ship_params
      params.require(:ship).permit(*SHIP_PARAM_KEYS)
    end
  end
end
