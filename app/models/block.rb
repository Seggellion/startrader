class Block < ApplicationRecord
  belongs_to :section
  has_one_attached :image

  validates :block_type, presence: true
  validates :position, presence: true

  # Update enum to use integer values
  enum :block_type, { image: 0, rich_text: 1, single_line_text: 2, json: 3 }

  default_scope { order(:position) }

  def image?
    block_type == "image" && image.attached?
  end
end
