module Admin
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
    before_action :require_admin

    layout 'admin'

    private

    def authenticate_user!
      unless current_user        
        redirect_to login_path # Redirect to the login page if the user is not logged in
      end
    end

    def require_admin      
      if current_user && !current_user.admin?
        redirect_to root_path, alert: "You do not have access to this page." # Redirect to root if the user is logged in but not an admin
      end
    end

    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end
  end
end
