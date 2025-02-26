# Be sure to restart your server when you modify this file.

# Rails.application.config.assets.precompile += ['manifest.js.erb']

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"
# config/initializers/assets.rb
Rails.application.config.assets.precompile += [
  "#{Rails.application.config.active_theme}/assets/config/manifest.js.erb"
]

Rails.application.config.assets.paths << Rails.root.join("app", "themes", Rails.application.config.active_theme, "assets", "stylesheets")
Rails.application.config.assets.paths << Rails.root.join("app", "themes", Rails.application.config.active_theme, "assets", "javascripts")
Rails.application.config.assets.paths << Rails.root.join("app", "themes", Rails.application.config.active_theme, "assets", "images")
Rails.application.config.assets.paths << Rails.root.join("app", "themes", Rails.application.config.active_theme, "assets", "fonts")


Rails.application.config.assets.precompile += %w( fonts.css )


                                                  
Rails.application.config.assets.precompile += %W( #{Rails.application.config.active_theme}.css )
Rails.application.config.assets.precompile += %w( *.eot *.svg *.ttf *.woff *.woff2 )
