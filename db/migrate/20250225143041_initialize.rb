class Initialize < ActiveRecord::Migration[8.0]
  def change


        create_table :action_text_rich_texts do |t|
          t.string :name, null: false
          t.text :body
          t.string :record_type, null: false
          t.bigint :record_id, null: false
          t.timestamps
        end
        add_index :action_text_rich_texts, [:record_type, :record_id, :name], unique: true, name: 'index_action_text_rich_texts_uniqueness'
    
        create_table :active_storage_attachments do |t|
          t.string :name, null: false
          t.string :record_type, null: false
          t.bigint :record_id, null: false
          t.bigint :blob_id, null: false
          t.timestamps
        end
        add_index :active_storage_attachments, :blob_id
        add_index :active_storage_attachments, [:record_type, :record_id, :name, :blob_id], unique: true, name: 'index_active_storage_attachments_uniqueness'
    
        create_table :active_storage_blobs do |t|
          t.string :key, null: false
          t.string :filename, null: false
          t.string :content_type
          t.text :metadata
          t.string :service_name, null: false
          t.bigint :byte_size, null: false
          t.string :checksum
          t.timestamps
        end
        add_index :active_storage_blobs, :key, unique: true
    
        create_table :active_storage_variant_records do |t|
          t.bigint :blob_id, null: false
          t.string :variation_digest, null: false
        end
        add_index :active_storage_variant_records, [:blob_id, :variation_digest], unique: true, name: 'index_active_storage_variant_records_uniqueness'
    

        create_table :users do |t|
          t.string :email, null: false
          t.string :uid, null: false
          t.string :provider
          t.string :username
          t.string :twitch_id
          t.integer :user_type
          t.string :first_name
          t.string :last_name
          t.string :avatar
          t.string :country
          t.datetime :last_login
          t.json :global_inventory, default: {}
          t.json :purchased_items, default: []
          t.timestamps
          t.index :uid, unique: true
        end
    

        create_table :articles do |t|
          t.string :title
          t.text :content
          t.bigint :user_id
          t.bigint :category_id
          t.string :slug
          t.text :meta_description
          t.text :meta_keywords
          t.boolean :published
          t.timestamps
        end
        add_index :articles, :category_id
        add_index :articles, :user_id
    
        create_table :categories do |t|
          t.string :name, null: false
          t.string :slug
          t.timestamps
        end
    
        create_table :cities do |t|
          t.string :name, null: false
          t.integer :population, default: 0
          t.boolean :is_starving, default: false
          t.string :mayor
          t.float :food_supply, default: 0.0
          t.float :wood_supply, default: 0.0
          t.float :metal_supply, default: 0.0
          t.float :stone_supply, default: 0.0
          t.float :textile_supply, default: 0.0
          t.float :technology_supply, default: 0.0
          t.bigint :shard_id
          t.timestamps
        end
        add_index :cities, :name, unique: true
        add_index :cities, :shard_id
    
      
        create_table :npcs do |t|
          t.string :npc_id, null: false
          t.string :npc_type, null: false
          t.string :city_name, null: false
          t.string :name
          t.string :gender
          t.text :description
          t.integer :level, default: 1
          t.integer :health, default: 100
          t.integer :mana, default: 50
          t.boolean :is_active, default: true
          t.jsonb :inventory, default: {}
          t.jsonb :stats, default: {}
          t.datetime :last_interaction_at
          t.datetime :spawned_at
          t.datetime :despawned_at
          t.string :spawn_location
          t.bigint :shard_id
          t.string :spawn_block_id
          t.timestamps
        end


  # 1) LOCATIONS
  create_table :locations do |t|
    t.string  :name,          null: false
    t.string  :classification # e.g. "planet", "moon", "station", "outpost"
    t.bigint  :parent_id,     index: true
    t.float   :mass
    t.float   :periapsis
    t.float   :apoapsis

    # Add other columns (images, color fields, etc.) as needed


 # ----- ADDED for Data API Compatibility -----
      # (TradeTerminal, Planets, Moons info)
      t.integer :api_id, index: true         # "id" from the data API
      t.integer :id_star_system
      t.integer :id_planet
      t.integer :id_orbit
      t.integer :id_moon
      t.integer :id_space_station
      t.integer :id_outpost
      t.integer :id_poi
      t.integer :id_city
      t.integer :id_faction
      t.integer :id_company

      t.string  :nickname
      t.string  :code
      t.string  :api_type           # Because "type" is a reserved column in Rails
      t.boolean :is_available,      default: false
      t.boolean :is_available_live, default: false
      t.boolean :is_visible,        default: false
      t.boolean :is_default_system, default: false
      t.boolean :is_affinity_influenceable, default: false
      t.boolean :is_habitation,     default: false
      t.boolean :is_refinery,       default: false
      t.boolean :is_cargo_center,   default: false
      t.boolean :is_medical,        default: false
      t.boolean :is_food,           default: false
      t.boolean :is_shop_fps,       default: false
      t.boolean :is_shop_vehicle,   default: false
      t.boolean :is_refuel,         default: false
      t.boolean :is_repair,         default: false
      t.boolean :is_nqa,            default: false
      t.boolean :is_player_owned,   default: false
      t.boolean :is_auto_load,      default: false
      t.boolean :has_loading_dock,  default: false
      t.boolean :has_docking_port,  default: false
      t.boolean :has_freight_elevator, default: false
      t.integer :date_added
      t.integer :date_modified
      t.string  :star_system_name
      t.string  :planet_name
      t.string  :orbit_name
      t.string  :moon_name
      t.string  :space_station_name
      t.string  :outpost_name
      t.string  :city_name
      t.string  :faction_name
      t.string  :company_name
      t.integer :max_container_size, default: 0

    t.timestamps
  end

  
  # Self-referential FK for nested orbits, if you want hierarchical relationships
  add_foreign_key :locations, :locations, column: :parent_id



  create_table :media do |t|
    t.string :file
    t.bigint :user_id
    t.text :meta_description
    t.text :meta_keywords
    t.boolean :approved
    t.boolean :screenshot_of_week
    t.string :category
    t.timestamps
    t.index :user_id
  end

     # 3) COMMODITIES
     create_table :commodities do |t|
      t.string  :name,                              null: false
      t.text    :description

      # ----- ADDED for Data API -----
      # e.g. "id": 1, "id_parent": 2, "name": "Agricium", "code": "AGRI", etc.
      t.integer :api_id,         index: true  # "id" from the external data
      t.integer :id_parent
      t.string  :code
      t.string  :kind
      t.float   :weight_scu
      t.decimal :price_buy,  precision: 15, scale: 2, default: 0
      t.decimal :price_sell, precision: 15, scale: 2, default: 0

      t.boolean :is_available,      default: false
      t.boolean :is_available_live, default: false
      t.boolean :is_visible,        default: false
      t.boolean :is_mineral,        default: false
      t.boolean :is_raw,            default: false
      t.boolean :is_refined,        default: false
      t.boolean :is_harvestable,    default: false
      t.boolean :is_buyable,        default: false
      t.boolean :is_sellable,       default: false
      t.boolean :is_temporary,      default: false
      t.boolean :is_illegal,        default: false
      t.boolean :is_fuel,           default: false

      t.string  :wiki
      t.integer :date_added
      t.integer :date_modified


      t.timestamps
    end

    
   # 4) PRODUCTION FACILITIES (storing commodity inventory here)
   create_table :production_facilities do |t|
    t.references :location,      null: false, foreign_key: true
    t.references :commodity,     null: false, foreign_key: true
    t.string     :facility_name
    t.integer    :production_rate
    t.integer    :consumption_rate
    # Inventory fields
    t.integer    :inventory,     default: 0
    t.integer    :max_inventory, default: 0
    t.decimal    :local_buy_price,  precision: 10, scale: 2, default: 0.0
    t.decimal    :local_sell_price, precision: 10, scale: 2, default: 0.0

      # ----- ADDED for "Raw Commodity Data" bridging terminal & commodity -----
      t.integer :api_id, index: true        # "id" from raw commodity-loc data
      t.integer :id_commodity              # matches "id_commodity" from API
      t.integer :id_terminal               # matches "id_terminal" from API

      # e.g. "price_buy": 0, "price_sell": 172500, ...
      t.decimal :price_buy,       precision: 15, scale: 2, default: 0
      t.decimal :price_buy_avg,   precision: 15, scale: 2, default: 0
      t.decimal :price_sell,      precision: 15, scale: 2, default: 0
      t.decimal :price_sell_avg,  precision: 15, scale: 2, default: 0
      t.integer :scu_buy,         default: 0
      t.integer :scu_buy_avg,     default: 0
      t.integer :scu_sell_stock,  default: 0
      t.integer :scu_sell_stock_avg, default: 0
      t.integer :scu_sell,        default: 0
      t.integer :scu_sell_avg,    default: 0
      t.integer :status_buy,      default: 0
      t.integer :status_sell,     default: 0
      t.string  :container_sizes
      t.integer :date_added
      t.integer :date_modified
      t.string  :commodity_name
      t.string  :terminal_name


    t.timestamps
  end


    # 5) SHIPS TABLE (reference data for ship models)
    create_table :ships do |t|
      t.string  :model,                      null: false
      t.integer :manufacturer_id
      t.integer :scu
      t.integer :crew
      t.integer :length
      t.integer :beam
      t.integer :height
      t.integer :msrp
      t.integer :year_introduced
      t.string  :ship_image_primary
      t.string  :ship_image_secondary
      t.string  :image_topdown
      t.float   :hyd_fuel_capacity
      t.float   :qnt_fuel_capacity
      t.float   :liquid_storage_capacity
      t.float   :mass
      t.string  :vehicle_type
      t.string  :career
      t.string  :role
      t.integer :size
      t.integer :hp
      t.integer :speed
      t.integer :afterburner_speed
      t.integer :ifcs_pitch_max
      t.integer :ifcs_yaw_max
      t.integer :ifcs_roll_max
      t.string  :shield_face_type
      t.integer :armor_physical_dmg_reduction
      t.integer :armor_energy_dmg_reduction
      t.integer :armor_distortion_dmg_reduction
      t.integer :armor_em_signal_reduction
      t.integer :armor_ir_signal_reduction
      t.integer :armor_cs_signal_reduction
      t.integer :capacitor_crew_load
      t.integer :capacitor_crew_regen
      t.integer :capacitor_turret_load
      t.integer :capacitor_turret_regen
      t.string  :alt_ship_name
      t.integer :component_size

      # ------------------------------------------------------------------
      # 🚀 ADDED COLUMNS FOR API COMPATIBILITY
      # ------------------------------------------------------------------
      t.integer :api_id, index: true             # "id" from the API
      t.integer :id_company                      # Manufacturer company ID
      t.integer :id_parent                       # Parent ship ID (e.g., loaners or variants)
      t.string  :ids_vehicles_loaners            # Loaner vehicle IDs
      t.string  :name_full                       # Full name of the ship
      t.string  :slug                            # SEO-friendly URL slug
      t.string  :uuid                            # UUID if available
      t.string  :crew_range                      # "1,2" or other range values
      t.string  :container_sizes                 # Potential cargo container sizes
      t.string  :pad_type                        # "S", "M", "L", etc.
      t.string  :game_version                    # "3.22.0b" or similar

      # Booleans for ship roles and capabilities
      t.boolean :is_addon,          default: false
      t.boolean :is_boarding,       default: false
      t.boolean :is_bomber,         default: false
      t.boolean :is_cargo,          default: false
      t.boolean :is_carrier,        default: false
      t.boolean :is_civilian,       default: false
      t.boolean :is_concept,        default: false
      t.boolean :is_construction,   default: false
      t.boolean :is_datarunner,     default: false
      t.boolean :is_docking,        default: false
      t.boolean :is_emp,            default: false
      t.boolean :is_exploration,    default: false
      t.boolean :is_ground_vehicle, default: false
      t.boolean :is_hangar,         default: false
      t.boolean :is_industrial,     default: false
      t.boolean :is_interdiction,   default: false
      t.boolean :is_loading_dock,   default: false
      t.boolean :is_medical,        default: false
      t.boolean :is_military,       default: false
      t.boolean :is_mining,         default: false
      t.boolean :is_passenger,      default: false
      t.boolean :is_qed,            default: false
      t.boolean :is_racing,         default: false
      t.boolean :is_refinery,       default: false
      t.boolean :is_refuel,         default: false
      t.boolean :is_repair,         default: false
      t.boolean :is_research,       default: false
      t.boolean :is_salvage,        default: false
      t.boolean :is_scanning,       default: false
      t.boolean :is_science,        default: false
      t.boolean :is_showdown_winner,default: false
      t.boolean :is_spaceship,      default: false
      t.boolean :is_starter,        default: false
      t.boolean :is_stealth,        default: false
      t.boolean :is_tractor_beam,   default: false
      t.boolean :is_quantum_capable,default: false

      # External links
      t.string :url_store
      t.string :url_brochure
      t.string :url_hotsite
      t.string :url_video
      t.text   :url_photos, default: "[]"

      # API metadata
      t.integer :date_added
      t.integer :date_modified
      t.string  :company_name

      t.timestamps
    end
    add_index :ships, :model, unique: true


        # 6) USER_SHIPS TABLE (instances of ships owned by a particular user)
        create_table :user_ships do |t|
          t.references :user,  null: false, foreign_key: true
          t.references :ship,  null: false, foreign_key: true
          t.integer    :total_scu
          t.integer    :used_scu
          t.string     :host_twitch_id
    
          t.timestamps
        end

    # 7) USER_SHIP_CARGOS (commodities loaded on a user’s ship)
    create_table :user_ship_cargos do |t|
      t.references :user_ship,  null: false, foreign_key: true
      t.references :commodity,  null: false, foreign_key: true
      t.integer    :scu,        default: 0
      t.decimal    :buy_price,  precision: 10, scale: 2
      t.decimal    :sell_price, precision: 10, scale: 2

      t.timestamps
    end

    # 8) STAR_BITIZEN_RUNS (records an actual trade run)
    create_table :star_bitizen_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.integer    :profit,        default: 0
      t.integer    :scu,           default: 0
      t.integer    :twitch_channel
      t.bigint     :buy_location_id
      t.bigint     :sell_location_id
      t.references :user_ship_cargo, foreign_key: true
      t.references :commodity,  null: false
      t.timestamps
    end

    # Add foreign keys to locations for buy/sell references
    add_foreign_key :star_bitizen_runs, :locations, column: :buy_location_id
    add_foreign_key :star_bitizen_runs, :locations, column: :sell_location_id
    add_foreign_key :star_bitizen_runs, :commodities, column: :commodity_id


    create_table :pages do |t|
      t.string :title, null: false
      t.bigint :user_id
      t.bigint :category_id
      t.text :content
      t.string :slug
      t.text :meta_description
      t.text :meta_keywords
      t.boolean :published
      t.string :template
      t.timestamps
      t.index :category_id
      t.index :user_id
    end

    create_table "sections", force: :cascade do |t|
      t.string "name", null: false
      t.string "template", null: false
      t.integer "animation_speed"
      t.integer "position"
      t.string "subtitle"
      t.text "body"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end
  
    create_table :terminals do |t|
      t.integer :id_star_system
      t.integer :id_planet
      t.integer :id_orbit
      t.integer :id_moon
      t.integer :id_space_station
      t.integer :id_outpost
      t.integer :id_poi
      t.integer :id_city
      t.integer :id_faction
      t.integer :id_company
      t.integer :api_id
      t.string :name
      t.string :nickname
      t.string :code
      t.integer :max_container_size
      t.references :location, foreign_key: true, index: true
      t.timestamps
    end

    create_table :blocks do |t|
      t.bigint :section_id, null: false
      t.integer :block_type, null: false
      t.text :content
      t.integer :position
      t.timestamps
      t.index :section_id
    end

    create_table "shard_user_skills", force: :cascade do |t|
      t.bigint "shard_user_id", null: false
      t.string "skill_name", null: false
      t.decimal "skill_value", precision: 5, scale: 1, default: "0.0", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["shard_user_id", "skill_name"], name: "index_shard_user_skills_on_shard_user_id_and_skill_name", unique: true
      t.index ["shard_user_id"], name: "index_shard_user_skills_on_shard_user_id"
    end
  
    create_table "shard_users", force: :cascade do |t|
      t.bigint "user_id", null: false
      t.bigint "shard_id"
      t.integer "karma", default: 0
      t.integer "fame", default: 0
      t.integer "murder_count", default: 0
      t.json "currency", default: {}
      t.json "inventory", default: {}
      t.json "stats", default: {}
      t.jsonb "last_location", default: {}
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["shard_id"], name: "index_shard_users_on_shard_id"
      t.index ["user_id"], name: "index_shard_users_on_user_id"
    end
  
    create_table "shards", force: :cascade do |t|
      t.string "name", null: false
      t.string "region", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end
  


    create_table :events do |t|
      t.string :title
      t.text :description
      t.string :location
      t.string :shard
      t.string :slug
      t.string :mode
      t.string :twitter
      t.string :discord
      t.string :facebook
      t.string :frequency
      t.string :sponsor
      t.string :timezone
      t.bigint :user_id
      t.bigint :category_id
      t.datetime :start_time
      t.datetime :end_time
      t.timestamps
      t.index :category_id
      t.index :user_id
    end

    
    create_table "menu_items" do |t|
      t.string "title"
      t.string "url"
      t.bigint "menu_id", null: false
      t.integer "parent_id"
      t.integer "position"
      t.integer "item_type", null: false, default: 0
      t.integer "item_id"
      t.timestamps
      t.index ["menu_id"], name: "index_menu_items_on_menu_id"
    end

    create_table "menus" do |t|
      t.string "name"
      t.timestamps
    end

    
    create_table "services" do |t|
      t.string "title", null: false
      t.text "content"
      t.bigint "category_id"
      t.string "slug"
      t.text "meta_description"
      t.text "meta_keywords"
      t.boolean "published"
      t.timestamps
      t.index ["category_id"], name: "index_services_on_category_id"
    end

    create_table "settings" do |t|
      t.string "key"
      t.text "value"
      t.string "group"
      t.string "setting_type"
      t.timestamps
    end


    create_table "contact_messages" do |t|
      t.string "first_name"
      t.string "last_name"
      t.string "email"
      t.string "phone"
      t.text "properties"
      t.string "subject"
      t.text "body"
      t.datetime "read_at"
      t.string "ip_address"
      t.string "country_code"
      t.timestamps
    end


    create_table "testimonials" do |t|
      t.string "title", null: false
      t.text "content"
      t.bigint "category_id"
      t.timestamps
      t.index ["category_id"], name: "index_testimonials_on_category_id"
    end

    create_table :comments do |t|
      t.text :content
      t.bigint :user_id
      t.string :commentable_type
      t.bigint :commentable_id
      t.timestamps
      t.index [:commentable_type, :commentable_id], name: "index_comments_on_commentable"
      t.index :user_id
    end


        add_index :npcs, :city_name
        add_index :npcs, :npc_id, unique: true
        add_index :npcs, :npc_type
        add_index :npcs, :shard_id
    

        
        add_foreign_key :active_storage_attachments, :active_storage_blobs, column: "blob_id"
        add_foreign_key :active_storage_variant_records, :active_storage_blobs, column: "blob_id"
        add_foreign_key :articles, :categories
        add_foreign_key :articles, :users
        add_foreign_key :blocks, :sections
        add_foreign_key :comments, :users
        add_foreign_key :events, :categories
        add_foreign_key :media, :users
        add_foreign_key :npcs, :shards
        add_foreign_key :pages, :categories
        add_foreign_key :pages, :users


  end
end
