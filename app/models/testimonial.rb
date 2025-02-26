class Testimonial < ApplicationRecord
    belongs_to :category, optional: true
  
    validates :title, presence: true
    validates :content, presence: true

    has_rich_text :content
    
    scope :by_category_name, ->(name) {
      joins(:category).where(categories: { slug: name })
    }
  end
  