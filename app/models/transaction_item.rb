class TransactionItem < ApplicationRecord
    belongs_to :parent_transaction, class_name: "Transaction", foreign_key: "transaction_id"
  
    validates :item_name, presence: true
    validates :quantity, numericality: { only_integer: true, greater_than: 0 }
    validates :price, numericality: { greater_than_or_equal_to: 0 }
  end
  