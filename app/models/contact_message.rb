class ContactMessage < ApplicationRecord
  validates :first_name, :last_name, :email, :subject, :body, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

  def self.unread_count
    where(read_at: nil).count
  end
end
