class PlayguideController < ApplicationController
    before_action :set_page, only: [:atlas]
    before_action :set_atlas_pages, only: [:atlas]

    def index
      render "pages/playguide"
    end



    def atlas
      render_template_for_page
    end
  
    private
  
    def set_page
      # Find the page based on the slug, default to "atlas" if slug is missing
      @page = Page.find_by!(slug: params[:slug] || 'atlas')
    rescue ActiveRecord::RecordNotFound
      render plain: 'Page not found', status: :not_found
    end
  
    def render_template_for_page
      theme_template_path = "pages/page-atlas" # Static path to your template in the theme folder
  
      if lookup_context.exists?(theme_template_path, [], false)
        render theme_template_path
      else
        render plain: "Template not found", status: :not_found
      end
    end

    def set_atlas_pages
        @atlas_pages = Page.where(template: 'atlas').order(:title)
      end
    


end