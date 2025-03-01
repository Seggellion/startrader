# app/models/terminal.rb

class Terminal < ApplicationRecord
  # We want to link terminals to locations via "location_name"
  belongs_to :location, optional: true, primary_key: :name, foreign_key: :location_name

  # Automatically assign location before saving the Terminal record
  before_save :assign_location
  
  private
  
  def assign_location
    # Match by exact location name
    self.location = Location.find_by('LOWER(name) = ?', location_name.downcase) if location_name.present?
  end
end
