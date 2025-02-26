class Service < ApplicationRecord
    belongs_to :category, optional: true
    has_rich_text :content
    has_many_attached :images
    validate :unique_slug_across_models
    validates :title, presence: true
    extend FriendlyId
    friendly_id :title, use: :slugged

private
    def unique_slug_across_models
      if Page.exists?(slug: slug)
        errors.add(:slug, 'must be unique across services and pages')
      end
    end
  end
  