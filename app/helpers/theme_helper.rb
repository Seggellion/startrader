module ThemeHelper
    def current_theme
      Rails.application.config.active_theme || 'Dusk'
    end
  end
  