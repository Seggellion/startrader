module Admin
    class EventsController < Admin::ApplicationController
      before_action :set_event, only: [:edit, :update, :destroy]
  
      def index
        @events = Event.all.order(start_time: :asc)
      end
  
      def new
        @event = Event.new
      end
  
      def create
        @event = Event.new(event_params)
        @event.update(user_id: current_user.id)
        if @event.save
          redirect_to admin_events_path, notice: 'Event was successfully created.'
        else
          render :new
        end
      end
  
      def edit; end
  
      def update
        if @event.update(event_params)
          redirect_to admin_events_path, notice: 'Event was successfully updated.'
        else
          render :edit
        end
      end
  
      def destroy
        @event.destroy
        redirect_to admin_events_path, notice: 'Event was successfully deleted.'
      end
  
      private
  
      def set_event
        @event = Event.find_by_slug(params[:id])
      end
  
      def event_params
        params.require(:event).permit(:title, :description, :location, :start_time, :end_time)
      end
    end
  end
  