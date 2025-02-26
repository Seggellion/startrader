# config/initializers/view_paths.rb
Rails.application.config.to_prepare do
    # This will prepend a custom path for all controllers.
    ActionController::Base.prepend_view_path(
      Rails.root.join("app", "themes")
    )
  end
  