class ThemesController < ApplicationController
  def set_theme
    theme = params[:theme]

    if theme.present? && valid_theme?(theme)
      # Update or create the 'current-theme' setting
      
      Setting.find_or_create_by(key: 'current-theme', setting_type:'text').update(value: theme)

      # Update Rails application config with the new active theme
      Rails.application.config.active_theme = theme

      flash[:notice] = "Theme changed to #{theme}"
    else
      flash[:alert] = "Invalid theme selection"
    end

    redirect_back fallback_location: root_path
  end

  private

  # Check if the theme exists in the app/themes directory
  def valid_theme?(theme)
    File.directory?(Rails.root.join("app", "themes", theme))
  end
end
