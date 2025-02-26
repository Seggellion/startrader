class ContactMessagesController < ApplicationController
    # before_action :set_contact_message, only: [:show]
  
    def new
      @contact_message = ContactMessage.new
    end
  
    def create
        
      @contact_message = ContactMessage.new(contact_message_params)

      @contact_message.ip_address = request.remote_ip
    
      # Disabled to reduce API calls for the short term
      # geolocation_data = Geolocation.get_location_from_ip(@contact_message.ip_address)
      # if geolocation_data[:error].nil?
      #  @contact_message.country_code = geolocation_data[:country_code]
      # else
      #  flash[:error] = "Could not determine location: #{geolocation_data[:error]}"
      # end

      @contact_message.country_code = "TE"

      @contact_message.email = params[:contact_message][:email].downcase
  
      if recently_sent?(@contact_message.email)
        flash[:alert] = "You can only send one message every 30 minutes."
        render :new and return
      end


      if @contact_message.save

        User.find_or_create_by(email: @contact_message.email.downcase, 
        first_name:@contact_message.first_name,
        last_name:@contact_message.last_name,
        user_type:50, 
        uid:0, 
        provider:'contact')

        respond_to do |format|
          format.json { render json: { success: true } }
          format.html { redirect_to root_path, notice: 'Message was successfully sent.' }
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, errors: @contact_message.errors.full_messages } }
          format.html { render :new }
        end
      end

    end
  
    private
  
    def set_contact_message
      @contact_message = ContactMessage.find(params[:id])
    end
  
    def contact_message_params
      params.require(:contact_message).permit(:first_name, :last_name, :email, :subject, :body)
    end
  
    def recently_sent?(email)
      ContactMessage.where(email: email).where('created_at >= ?', 30.minutes.ago).exists?
    end
  end
  