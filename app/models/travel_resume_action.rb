class TravelResumeAction < ApplicationRecord
  belongs_to :admin_user, class_name: 'User', optional: true
  validates :travel_guid, :ship_travel_id, :user_ship_id, :actor_label, :reason, presence: true
  validates :actor_kind, inclusion: {in: %w[admin operator]}
  validates :reason, length: {minimum: 3, maximum: 1000}
end
