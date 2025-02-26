class PagesController < ApplicationController
    before_action :set_page, only: [:show]
    before_action :prepend_theme_view_path
    def show
      # Template paths
      template_file = @page.template_file.presence || 'default'
      theme_template_path = "pages/page-#{template_file}" # E.g., "pages/page-contact"
      fallback_template = "pages/page-default"           # Default fallback
  
      # Render template based on existence in theme folder
      if lookup_context.exists?(theme_template_path, [], false)
        render theme_template_path
      else
        render fallback_template
      end
    end
    

    def index
      @pages = Page.all
    end
 
    private
    def prepend_theme_view_path
      theme_path = Rails.root.join("app", "themes", current_theme, "views")
      prepend_view_path theme_path
    end

    
    def set_page
      @page = Page.friendly.find(params[:slug])
    end
  end
  