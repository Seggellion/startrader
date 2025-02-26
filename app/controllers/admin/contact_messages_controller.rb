module Admin
  class ContactMessagesController < Admin::ApplicationController
    before_action :set_contact_message, only: [:show]

    def index
      @contact_messages = ContactMessage.all
    end

    def show
      @contact_message.update(read_at: Time.current) unless @contact_message.read_at
    end

    private

    def set_contact_message
      @contact_message = ContactMessage.find(params[:id])
    end
  end
end
