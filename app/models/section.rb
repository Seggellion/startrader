class Section < ApplicationRecord
    has_many :blocks, -> { order(:position) }, dependent: :destroy
  
    validates :name, presence: true
    validates :template, presence: true
  
    default_scope { order(:position) }
  end
  