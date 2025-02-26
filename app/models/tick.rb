class Tick < ApplicationRecord
    validates :sequence, presence: true, numericality: { only_integer: true }
  
    # Example method to process a game tick
    def process_tick
      ProductionFacility.find_each(&:produce)
      ProductionFacility.find_each(&:consume)
      update!(processed_at: Time.current)
    end
  end
  