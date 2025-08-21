class EventsController < ApplicationController
  before_action :prepend_theme_view_path, except: [:send_check_status]
    def index
        @events = Event.all.order(start_time: :asc)
      end
    
      def show
        @event = Event.friendly.find(params[:slug])
      end

  def send_check_status
    
    RabbitmqSender.send_event(params[:streamer])
    redirect_back fallback_location: root_path, notice: "Message sent to #{params[:streamer]}"
  end

      private
    
      def prepend_theme_view_path
        # current_theme should match the folder name under app/themes/
        theme_path = Rails.root.join("app", "themes", current_theme, "views")
        prepend_view_path theme_path
      end
end
