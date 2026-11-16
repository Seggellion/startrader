class Shard < ApplicationRecord
    # Associations
    has_many :cities, dependent: :destroy
    has_many :city_commodities, dependent: :destroy
    has_many :npcs, dependent: :destroy
    has_many :transactions, dependent: :destroy
    has_many :shard_users, dependent: :destroy
    has_many :user_ships
    has_many :users, through: :shard_users
  
    # Validations
    validates :name, presence: true, uniqueness: true
    validates :region, presence: true
    validate :channel_uuid_unique_when_normalized

    # F-04: the external shard identity (channel_uuid) is matched case- and
    # whitespace-insensitively everywhere (status, travel, trades).
    def self.normalize_channel_uuid(value)
      value.to_s.strip.downcase.presence
    end

    def self.lookup_channel_uuid(value)
      key = normalize_channel_uuid(value)
      return unless key

      matches = where('lower(btrim(channel_uuid)) = ?', key).limit(2).to_a
      if matches.size > 1
        raise ActiveRecord::RecordNotFound, 'Multiple shards match this shard_uuid; administrator review is required.'
      end
      matches.first
    end
  
    # Scopes
    scope :with_active_npcs, -> { includes(:npcs).where(npcs: { is_active: true }) }

  
    private

    def channel_uuid_unique_when_normalized
      key = self.class.normalize_channel_uuid(channel_uuid)
      return unless key

      clash = self.class.where('lower(btrim(channel_uuid)) = ?', key).where.not(id: id).exists?
      errors.add(:channel_uuid, 'matches another shard (case/whitespace-insensitive)') if clash
    end
  end
  
