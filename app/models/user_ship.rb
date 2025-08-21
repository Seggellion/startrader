# app/models/user_ship.rb
class UserShip < ApplicationRecord
  belongs_to :user
  belongs_to :ship

  belongs_to :shard, optional: true
  belongs_to :shard_user, optional: true

  has_many :user_ship_cargos
  belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true

  validates :total_scu, :used_scu, presence: true

  has_one :active_travel, -> { where(is_paused: false).where('arrival_tick >= ?', Tick.current) }, class_name: 'ShipTravel'
  has_one :ship_travel
  
  # keep shard_user in sync if missing but user_id+shard_id exist
  before_validation :infer_shard_user

  validate :shard_user_consistency

  def available_cargo_space = total_scu - used_scu

  def add_cargo_scu(scu)
    new_used_scu = [used_scu.to_i + scu.to_i, total_scu.to_i].min
    update!(used_scu: new_used_scu)
  end

  def remove_cargo_scu(scu)
    new_used_scu = [used_scu.to_i - scu.to_i, 0].max
    update!(used_scu: new_used_scu)
  end

  private

  def infer_shard_user
    return if shard_user_id.present? || user_id.blank? || shard_id.blank?
    self.shard_user = ShardUser.find_by(user_id: user_id, shard_id: shard_id)
  end

  def shard_user_consistency
    return if shard_user.blank?
    errors.add(:user_id,  'must match shard_user.user_id')  if shard_user.user_id != user_id
    errors.add(:shard_id, 'must match shard_user.shard_id') if shard_user.shard_id != shard_id
  end
end
