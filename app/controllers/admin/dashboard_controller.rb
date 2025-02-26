module Admin
  class DashboardController < ApplicationController
    layout 'admin'

    def index
      @pages = Page.all      
      # Admin dashboard logic
    end
  end
end
