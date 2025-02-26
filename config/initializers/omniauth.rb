# config/initializers/omniauth.rb

Rails.application.config.middleware.use OmniAuth::Builder do

    provider :discord, Setting.get('discord_client_id'), Setting.get('discord_client_secret'), scope: 'identify email'
  
    provider :twitch, Setting.get('twitch_client_id'), Setting.get('twitch_secret'), scope: 'user:read:email'

  end
  