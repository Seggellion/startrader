class ContactMailer < ApplicationMailer
    require 'sendgrid-ruby'
    include SendGrid
  
    def new_message_email(contact_message)
      @contact_message = contact_message
      from = Email.new(email: 'segellion@altama.ca')
      to = Email.new(email: Setting.get('notification-email'))
      subject = @contact_message.subject
      content = Content.new(type: 'text/plain', value: @contact_message.body)
      
  
      mail = Mail.new(from, subject, to, content)
      
      sg = SendGrid::API.new(api_key: Setting.get('sendgrid_api_key'))
      response = sg.client.mail._('send').post(request_body: mail.to_json)
      if response.status_code.to_i.between?(200, 299)
        Rails.logger.info("Email sent successfully with status code #{response.status_code}")
      else
        Rails.logger.error("Failed to send email with status code #{response.status_code}")
      end
    end

  end
  