# app/controllers/concerns/secret_guid_auth.rb
module SecretGuidAuth
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_secret_guid!
  end

  private

  def authenticate_secret_guid!
    return if performed?

    provided = request.headers['X-Secret-Guid'].presence ||
      params[:secret_guid].presence ||
      nested_param_value(params, :trade, :secret_guid).presence ||
      parsed_json_value(:secret_guid).presence ||
      parsed_json_value(:secret_guid, parent: :trade).presence
    expected = Setting.get('secret_guid').to_s.presence || Setting.get('secret-guid').to_s.presence

    unless provided && expected && secure_equal?(provided, expected)
      render json: secret_guid_auth_error_response, status: :unauthorized and return
    end
  end

  def secret_guid_auth_error_response
    { error: 'Unauthorized' }
  end

  def parsed_json_value(key, parent: nil)
    return unless defined?(@json_payload) && @json_payload.respond_to?(:[])

    source = parent ? nested_param_source(@json_payload, parent) : @json_payload
    return unless source.respond_to?(:[])

    source[key.to_s] || source[key.to_sym]
  end

  def nested_param_value(source, parent, key)
    child = nested_param_source(source, parent)
    return unless child.respond_to?(:[])

    child[key] || child[key.to_s]
  end

  def nested_param_source(source, key)
    return unless source.respond_to?(:[])

    source[key] || source[key.to_s]
  end

  # Use a timing-safe compare by hashing to equalize length first
  def secure_equal?(a, b)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(a),
      Digest::SHA256.hexdigest(b)
    )
  end
end
