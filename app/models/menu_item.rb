class MenuItem < ApplicationRecord
  belongs_to :menu
  belongs_to :parent, class_name: 'MenuItem', optional: true
  has_many :children, class_name: 'MenuItem', foreign_key: 'parent_name', dependent: :destroy
  enum :item_type, { custom: 0, page: 1, category: 2, service: 3 }

  validates :url, presence: true
  acts_as_list scope: -> { where(menu_id: menu_id) }
  scope :roots, -> { where(parent_name: nil) }

end
