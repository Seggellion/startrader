class User < ApplicationRecord
    has_many :pages, dependent: :destroy

    has_many :media, dependent: :destroy
    has_many :comments, dependent: :destroy
    has_many :contact_messages, foreign_key: :email, primary_key: :email
    has_many :articles, dependent: :destroy
    has_many :shard_users, dependent: :destroy

  store :global_inventory, coder: JSON
  store :purchased_items, coder: JSON

  has_many :user_ships
  has_many :ships, through: :user_ships
  has_many :star_bitizen_runs

  validates :username, :twitch_id, presence: true


    # Example method to add a purchased item
    def add_purchased_item(item_name)
      self.purchased_items ||= []
      self.purchased_items << { name: item_name, purchased_at: Time.current }
      save
    end

    validates :uid, presence: true, uniqueness: true
    has_one_attached :avatar

  # Define roles
  enum :user_type, { admin: 0, player: 1 }

  

  def self.admin_exists?
    where(user_type: :admin).exists?
  end

  def admin?
    user_type == 'admin'
  end

 # Example method to get user's active ship
 def active_ship
  user_ships.first # You could expand this to support "selected" ship logic
end

def update_credits(amount)
  new_balance = wallet_balance.to_f + amount.to_f
  
  update(wallet_balance: new_balance)
end

  end
  