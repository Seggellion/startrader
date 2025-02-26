class Category < ApplicationRecord
    has_many :services
    has_many :testimonials
    has_many :pages
    has_many :articles
    has_many :posts
    has_many :categories
  
    validates :name, presence: true
    extend FriendlyId
    friendly_id :name, use: :slugged
      # Ensure the slug is generated when the name is defined
    def should_generate_new_friendly_id?
      name_changed? || slug.blank?
    end
  end
  