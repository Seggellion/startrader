class Menu < ApplicationRecord
    has_many :menu_items, -> { order(position: :asc) }, dependent: :destroy

    def self.for_location(location)
        where('LOWER(name) = ?', location.downcase).first&.menu_items&.roots
      end
end
