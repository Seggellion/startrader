class TickControl < ApplicationRecord
  # Singleton row to hold the on/off state
  def self.instance
    first || create!(running: false)
  end

  def start! = update!(running: true)
  def stop!  = update!(running: false)
end