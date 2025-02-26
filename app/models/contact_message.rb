class ContactMessage < ApplicationRecord
    belongs_to :user, foreign_key: :email, primary_key: :email, optional: true
  
    validates :first_name, :last_name, :email, :subject, :body, presence: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  
    before_save :set_user
  
    def self.unread_count
        where(read_at: nil).count
      end

    private
  
    def set_user
      self.user = User.find_or_create_by(email: email.downcase)
    end
  end
  