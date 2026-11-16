class MenuItem < ApplicationRecord
  belongs_to :menu
  belongs_to :parent, class_name: 'MenuItem', optional: true
  has_many :children, class_name: 'MenuItem', foreign_key: 'parent_id', dependent: :destroy
  enum :item_type, { custom: 0, page: 1, category: 2, service: 3 }

  validates :url, presence: true
  validate :valid_parent_tree
  acts_as_list scope: :menu
  scope :roots, -> { where(parent_id: nil) }

  private

  def valid_parent_tree
    return if parent_id.blank?
    if parent.nil? || parent.menu_id != menu_id
      errors.add(:parent, "must belong to this menu")
      return
    end

    seen = [id].compact
    ancestor = parent
    while ancestor
      if seen.include?(ancestor.id)
        errors.add(:parent, "cannot form a cycle")
        return
      end
      seen << ancestor.id
      ancestor = ancestor.parent
    end
  end
end
