Rails.application.routes.draw do
  # Health Check
  get 'up', to: 'rails/health#show', as: :rails_health_check

  # Authentication & Sessions
  get '/auth/:provider/callback', to: 'sessions#create'
  get '/auth/failure', to: redirect('/')
  get '/discord_login', to: redirect('/auth/discord'), as: 'discord_login'
  get '/auth/twitch/callback', to: 'sessions#create'
  get '/login', to: 'sessions#new', as: 'login'
  delete '/logout', to: 'sessions#destroy', as: 'logout'

  # Public Routes
  root 'home#index'
  get 'news', to: 'home#news'
  get 'economy', to: 'economy#index'
  get 'account/login', to: 'account#login'
  get 'account', to: 'account#show'
  get 'update-center', to: 'update_center#index'
  get 'update-center/fyi', to: 'update_center#fyi', as: 'update_center_fyi'
  get 'footer', to: 'menus#footer'
  get 'playguide', to: 'playguide#index'
  get 'playguide/atlas', to: 'playguide#atlas', defaults: { slug: 'atlas' }
  get 'playguide/atlas/:slug', to: 'playguide#atlas', as: 'atlas_page'
  post 'set_theme', to: 'themes#set_theme', as: :set_theme
  get '/shard/:name', to: 'star_bitizen_runs#shard_index', as: :shard_runs

  # Menu & Menu Items
  resources :menus, only: [:index, :new, :create, :edit, :update, :destroy] do
    resources :menu_items, only: [:new, :create, :edit, :update, :destroy] do
      member do
        patch :move_up
        patch :move_down
        patch :update_parent
      end
    end
  end

  # Locations
  resources :locations, only: [:index] do
    collection do
      get 'by_star', to: 'locations#index'
    end
  end

  # Users
  resources :users do
    member do
      get :edit_minecraft_uuid
      patch :update_minecraft_uuid
    end
  end

  # Products & Cart
  resources :products, only: [:index, :show], param: :handle do
    post 'add_to_cart', on: :member
  end
  get '/cart', to: 'products#cart', as: :cart
  get 'checkout', to: 'products#checkout'
  delete 'cart/remove/:line_id', to: 'products#remove_from_cart', as: 'remove_from_cart'

  # Events
  resources :events, only: [:index, :show], param: :slug

  # Services, Contact Messages, and Community
  resources :services, only: [:index, :show]
  resources :contact_messages, only: [:new, :create]

  resources :community, only: [] do
    collection do
      post :create_medium
      get :screenshots
      get :user_screenshots
    end
  end

  # API Namespace
  namespace :api do
    resources :ship_travel, only: [:create]
    get 'location/:user_ship_id', to: 'travel#location', as: 'location'
    post 'distance_calculator', to: 'distance_calculator#calculate'
    post 'set_tick', to: 'tick#set'
    post 'increment_tick', to: 'tick#increment'
    post 'buy', to: 'trades#buy'
    post 'sell', to: 'trades#sell'
    post 'status', to: 'trades#status'
    post 'gate_travel', to: 'gate_travel#gate_travel'
    delete "cancel", to: "ship_travel#destroy"

    resources :commands, only: [] do
      collection do
        post :buy
        post :sell
      end
    end

    resources :user_ships, only: [] do
      post :move, to: 'moves#create'
      get :location, to: 'locations#show'
    end

    resources :transactions, only: [:create]
    resources :npcs, only: [:create, :destroy]

    resources :shard_users, only: [] do
      member do
        post :adjust_stats
      end
    end

    resources :cities, only: [] do
      member do
        get :trade_data
        get :food_and_wood_supply
        get :food_supply
        get :starvation_status
      end
      collection do
        post :consume_commodities
        get :starving
      end
    end
  end

  # Admin Namespace
  namespace :admin do
    root to: 'dashboard#index'

    resources :planets, :user_ships, :user_ship_cargos, :star_bitizen_runs, :shards, :shard_users, :ship_travels, :cities, :outposts, :terminals, :moons, :vehicles, :space_stations, :star_systems, :production_facilities, only: [:index, :new, :create, :edit, :update, :destroy] do
      collection do
        delete :delete_all
      end
    end

    resources :commodities

    resources :data, only: [:index] do
      collection do
        post :import_ships
        post :import_commodities
        post :populate_facilities
        post :import_locations
        post :import_terminals
        post :import_planets
        post :import_moons
        post :import_outposts
        post :import_stations
        post :import_star_systems
        post :import_cities
      end
    end

    resources :locations, :articles, :testimonials, :pages, :posts, :comments, :users, :categories, :events, :settings, :services, :contact_messages, only: [:index, :show, :create, :edit, :update, :destroy]

    resources :articles, :pages, :services do
      member do
        patch :update_category
      end
    end

    resources :menus do
      resources :menu_items do
        patch :move_up, on: :member
        patch :move_down, on: :member
        patch :update_parent
      end
    end

    resources :media, only: [:index, :destroy] do
      collection do
        get :screenshots
      end
      member do
        patch :approve
        delete :reject
      end
    end

    resources :sections do
      member do
        patch :move_up
        patch :move_down
      end
      resources :blocks, only: [:new, :create, :edit, :update, :destroy] do
        member do
          patch :move_up
          patch :move_down
          patch :update
        end
      end
    end
  end

  # Catch-All Route for Pages
  get '/:slug', to: 'pages#show', constraints: lambda { |req|
    !req.path.starts_with?('api', '/services', '/admin', '/pages', '/auth', '/logout', '/events', '/economy', '/update-center', '/account', '/community', '/playguide', '/news')
  }, as: :catch_all_page
end
