class UserShipCargo < ApplicationRecord
  belongs_to :user_ship
  belongs_to :commodity

  has_many :star_bitizen_runs, foreign_key: :user_ship_cargo_id

  before_save :capture_previous_user_ship_for_recalculation, if: :user_ship_id_changed_after_persist?
  before_destroy :capture_current_user_ship_for_recalculation
  before_destroy :nullify_star_bitizen_runs
  after_commit :recalculate_user_ship_used_scu, on: [:create, :update, :destroy]

  validates :scu, numericality: { greater_than_or_equal_to: 0 }

  def potential_profit
    (sell_price - buy_price) * scu
  end

  private

  def user_ship_id_changed_after_persist?
    persisted? && will_save_change_to_user_ship_id?
  end

  def capture_previous_user_ship_for_recalculation
    user_ship_ids_for_recalculation << user_ship_id_in_database
  end

  def capture_current_user_ship_for_recalculation
    user_ship_ids_for_recalculation << user_ship_id
  end

  def recalculate_user_ship_used_scu
    user_ship_ids_for_recalculation << user_ship_id
    UserShip.where(id: user_ship_ids_for_recalculation.compact.uniq).find_each(&:recalculate_used_scu!)
  end

  def user_ship_ids_for_recalculation
    @user_ship_ids_for_recalculation ||= []
  end

  def nullify_star_bitizen_runs
    star_bitizen_runs.update_all(user_ship_cargo_id: nil)
  end
end
