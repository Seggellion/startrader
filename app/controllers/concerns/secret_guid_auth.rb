# app/controllers/concerns/secret_guid_auth.rb
module SecretGuidAuth
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_secret_guid!
  end

  private

  def authenticate_secret_guid!
    provided = request.headers['X-Secret-Guid'].presence || params[:secret_guid].presence
    expected = Setting.get('secret_guid').to_s.presence

    unless provided && expected && secure_equal?(provided, expected)
      render json: { error: 'Unauthorized' }, status: :unauthorized and return
    end
  end

  # Use a timing-safe compare by hashing to equalize length first
  def secure_equal?(a, b)
    ActiveSupport::SecurityUtils.secure_compare(
      Digest::SHA256.hexdigest(a),
      Digest::SHA256.hexdigest(b)
    )
  end
end
