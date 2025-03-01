# app/models/travel.rb
class ShipTravel < ApplicationRecord
  belongs_to :user_ship
  belongs_to :from_location, class_name: 'Location'
  belongs_to :to_location, class_name: 'Location'

  validates :departure_tick, :arrival_tick, presence: true
end
