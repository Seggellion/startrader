class Page < ApplicationRecord
    belongs_to :user
    has_rich_text :content

    validates :title, presence: true

    validate :unique_slug_across_models
    has_many_attached :images
    extend FriendlyId
    friendly_id :title, use: :slugged

    has_many :comments, as: :commentable
    belongs_to :category, optional: true


    def template_file
      template.present? ? template : 'show'
    end

    private

    def unique_slug_across_models
      if Service.exists?(slug: slug)
        errors.add(:slug, 'must be unique across pages and services')
      end
    end

  end
  