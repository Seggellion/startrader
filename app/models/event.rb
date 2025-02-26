class Event < ApplicationRecord
    validates :title, :location, :start_time, :end_time, presence: true
    validates :start_time, comparison: { less_than: :end_time }
    belongs_to :category, optional: true # Adjust based on your requirements
    belongs_to :user

    has_rich_text :description


    extend FriendlyId
    friendly_id :title, use: :slugged

    def formatted_time
      "#{start_time.strftime('%B %d, %Y %I:%M %p')} - #{end_time.strftime('%I:%M %p')}"
    end


    def organizer
      self.user.username
    end

    def address_line1
        parse_location[0] # Assuming the first part is the address line 1
      end
    
      def address_line2
        nil # Or parse for line2 if applicable
      end
    
      def city
        parse_location[1] # Second part is the city
      end
    
      def state_short
        parse_location[2] # Third part is the province/state
      end
    
      def zip
        parse_location[3] # Fourth part is the postal code
      end

    private



    def parse_location
        # Splits the location by commas and strips any leading/trailing whitespace from each part
        location.split(',').map(&:strip)
    end
end
