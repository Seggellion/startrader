class ApplicationController < ActionController::Base
    before_action :set_services
    before_action :load_menu
    before_action :set_theme_view_path

    before_action :include_theme_helpers
    before_action :set_active_theme
    helper_method :current_user


    before_action :prepend_theme_paths
    before_action :set_active_storage_url_options

    
    private


    def set_active_storage_url_options
      ActiveStorage::Current.url_options = { host: request.base_url }
    end
    
    def set_services
        @services = Service.all
    end

    def include_theme_helpers
        theme_helper = Rails.root.join("app", "themes", current_theme, "helpers", "theme_helper.rb")
        require_dependency theme_helper if File.exist?(theme_helper)
      end


      def prepend_theme_paths
        prepend_view_path Rails.root.join("app", "themes", "Dusk", "views")
      end

    
    def load_menu
        @header_menu_items = Menu.for_location('header')
        @footer_menu_items = Menu.for_location('footer')
      end

      def set_theme_view_path
        theme_path = Rails.root.join("app", "themes", current_theme, "views")
        prepend_view_path(theme_path) if File.directory?(theme_path)
      end

      def set_active_theme
        Rails.application.config.active_theme = Setting.get('current-theme') || 'Dusk'
      end
      
      def authenticate_user!
        unless current_user
          redirect_to login_path, alert: "You need to sign in to continue."
        end
      end

      def current_user
        @current_user ||= User.find_by(id: session[:user_id])
      end

      def current_theme
        Rails.application.config.active_theme || 'Dusk'
      end

end
