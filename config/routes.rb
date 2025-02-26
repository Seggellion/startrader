Rails.application.routes.draw do
  get 'menu_items/new'
  get 'menu_items/create'
  get 'menu_items/edit'
  get 'menu_items/update'
  get 'menu_items/destroy'
  get 'menus/index'
  get 'menus/new'
  get 'menus/create'
  get 'menus/edit'
  get 'menus/update'
  get 'menus/destroy'

  resources :users do
    member do
      get :edit_minecraft_uuid
      patch :update_minecraft_uuid
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check


  # Define the Discord OAuth routes
  get '/auth/:provider/callback', to: 'sessions#create'
  get '/auth/failure', to: redirect('/')
  get '/discord_login', to: redirect('/auth/discord'), as: 'discord_login'
    get '/auth/twitch/callback', to: 'sessions#create'


  delete '/logout', to: 'sessions#destroy', as: 'logout'
  # Route to your custom login page
  get '/login', to: 'sessions#new', as: 'login' 



  namespace :api do
      post 'commands/travel', to: 'commands#travel'
      post 'commands/buy',    to: 'commands#buy'
      post 'commands/sell',   to: 'commands#sell'
    end

  
  resources :services, only: [:index, :show]
  resources :contact_messages, only: [:new, :create]
  resources :events, only: [:index, :show], param: :slug
  resources :products, only: [:index, :show], param: :handle do
    post 'add_to_cart', on: :member
  end

  get '/cart', to: 'products#cart', as: :cart
  get 'checkout', to: 'products#checkout'
  delete 'cart/remove/:line_id', to: 'products#remove_from_cart', as: 'remove_from_cart'



  namespace :admin do
    resources :planets
    resources :cities
    resources :outposts
    resources :terminals
    resources :moons
    resources :vehicles
    resources :commodities
    resources :space_stations
    resources :star_systems
    resources :production_facilities

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


    resources :articles do
      member do
        patch :update_category
      end
    end
    resources :testimonials
    resources :pages do
      member do
        patch :update_category
      end
    end
    resources :media, only: [:index, :destroy] do
      collection do
        get :screenshots, action: :screenshots # Creates admin_screenshots_path
      end
  
      member do
        patch :approve
        delete :reject
      end
    end
    resources :posts
    resources :comments
    resources :users
    resources :categories
    resources :events
    resources :settings
    resources :services do
      member do
        patch :update_category
        patch :featured_image
      end
    end
    resources :contact_messages, only: [:index, :show]
    resources :menus do
      resources :menu_items do
        patch :move_up, on: :member
        patch :move_down, on: :member
        patch :update_parent
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

    root to: 'dashboard#index'
  end

    # Catch-all route for pages based on slug, excluding specific paths
    get '/:slug', to: 'pages#show', constraints: lambda { |req|
      !req.path.starts_with?('api','/services', '/admin', '/pages', '/auth', '/logout', '/events', '/economy', '/update-center','/account','/community', '/playguide', '/news')
    }, as: :catch_all_page

# config/routes.rb
namespace :api do
  #post 'cities/sync', to: 'cities#sync'
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

resources :community, only: [] do
  collection do
    post :create_medium
    get :screenshots
  end
end

    get 'pages', to: 'pages#index'
     get 'news', to: 'home#news'
    get 'economy', to: 'economy#index'
    get 'account/login', to: 'account#login'
    get 'account', to: 'account#show'
    get 'update-center', to: 'update_center#index'
    get 'update-center/fyi', to: 'update_center#fyi', as: 'update_center_fyi'
    get 'footer', to: 'menus#footer'
    get '/community/user_screenshots', to: 'community#user_screenshots'
    get 'playguide', to: 'playguide#index'
    get 'playguide/atlas', to: 'playguide#atlas', defaults: { slug: 'atlas' }
    get 'playguide/atlas/:slug', to: 'playguide#atlas', as: 'atlas_page'
  
  # Defines the root path route ("/")
   root "home#index"

   post 'set_theme', to: 'themes#set_theme', as: :set_theme


end
