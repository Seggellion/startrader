class UsersController < ApplicationController
  # M06 / S2 (F-11): these JSON routes expose every account; admins only.
  before_action :require_admin_json!
  # Explicit minimal fields: serializing whole User records overflowed the stack
  # (500 for every caller) and would expose more than an operator needs.
  PUBLIC_FIELDS = %w[id username uid twitch_id provider user_type created_at updated_at].freeze

  def index
    render json: User.order(:id).map { |user| user_json(user) }
  end

  def show
    user = User.find(params[:id])
    render json: user_json(user)
  end

  def create
    user = User.new(user_params)
    if user.save
      render json: user_json(user), status: :created
    else
      render json: user.errors, status: :unprocessable_entity
    end
  end

  private

  def user_json(user)
    user.attributes.slice(*PUBLIC_FIELDS)
  end

  def require_admin_json!
    return if current_user&.admin?

    render json: { error: current_user ? 'Forbidden' : 'Unauthorized' },
      status: current_user ? :forbidden : :unauthorized
  end


  def user_params
    params.require(:user).permit(:username, :user_twitch_id, :user_wallet, :user_type)
  end
end
