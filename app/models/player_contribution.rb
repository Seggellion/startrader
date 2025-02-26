class PlayerContribution < ApplicationRecord
    belongs_to :city
  
    validates :player_uuid, presence: true
    validates :commodity_type, presence: true
    validates :commodity_name, presence: true
    validates :player_name, presence: true
  
    # Example method to update contributions
     def add_contribution(amount)
       self.total_contribution += amount
       self.save!
     end
  
     def update_biggest_single(amount)
       self.biggest_single = amount if amount > self.biggest_single
       self.save!
     end
  end
  