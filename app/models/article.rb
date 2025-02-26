class Article < ApplicationRecord
    belongs_to :user
    has_rich_text :content
    belongs_to :category, optional: true

    validates :title, presence: true
    extend FriendlyId
    friendly_id :title, use: :slugged
    has_one_attached :image

  end
  