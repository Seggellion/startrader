module Api
  class BaseController < ActionController::API
    before_action :parse_json_request

    include SecretGuidAuth

    private

    def parse_json_request
      return unless request.media_type == 'application/json'

      request.body.rewind
      @json_payload = JSON.parse(request.body.read)
    rescue JSON::ParserError
      render json: { error: 'Invalid JSON payload' }, status: :bad_request and return
    end
  end
end
