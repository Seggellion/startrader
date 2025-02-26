class Post < ApplicationRecord
    belongs_to :user
    has_many :comments, as: :commentable
    belongs_to :category, optional: true

    validates :title, presence: true
  end
  