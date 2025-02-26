module Api
      class BaseController < ActionController::API
        before_action :parse_json_request
        before_action :validate_secret_guid
  
        private
  
        # 1. Parse JSON
        def parse_json_request
          # If the request has a JSON content type, parse it
          if request.content_type == 'application/json'
            begin
              @json_payload = JSON.parse(request.body.read)
            rescue JSON::ParserError
              render json: { error: 'Invalid JSON payload' }, status: :bad_request
            end
          end
        end
  
        # 2. Validate the secret GUID
        def validate_secret_guid
          # You can fetch from headers or params
          # Example: from custom header 'X-Secret-GUID'
          secret_guid = request.headers['X-Secret-Guid'] || params[:secret_guid]
  
          # Compare with your environment variable or Rails credential
          expected_guid = ENV['SECRET_GUID'] || 'YOUR_STATIC_GUID_FOR_DEV'
  
          unless secret_guid.present? && secret_guid == expected_guid
            render json: { error: 'Unauthorized - invalid secret GUID' }, status: :unauthorized
          end
        end
      end

  end
  