class Medium < ApplicationRecord
    belongs_to :user
    has_one_attached :file # ActiveStorage association

    validates :file, presence: true

    CATEGORIES = %w[screenshot content_page other].freeze

    validates :category, inclusion: { in: CATEGORIES }
  
    scope :screenshots, -> { where(category: 'screenshot') }

  end
  