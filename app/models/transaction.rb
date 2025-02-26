class Transaction < ApplicationRecord
    has_many :transaction_items, dependent: :destroy
    belongs_to :city, optional: true # Optional if not all transactions are tied to a city

    validates :player_uuid, presence: true
    validates :transaction_type, presence: true
    validates :total_price, numericality: { greater_than_or_equal_to: 0 }
  
    accepts_nested_attributes_for :transaction_items
  end
  