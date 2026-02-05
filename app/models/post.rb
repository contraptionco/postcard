# frozen_string_literal: true

class Post < ApplicationRecord
  audited associated_with: :account

  belongs_to :account, touch: true

  has_one :pinned_by, class_name: 'Account', inverse_of: :pinned_post, dependent: :nullify, foreign_key: :pinned_post_id

  has_many :email_messages, dependent: :destroy

  # Wabi-sabi mode: store the photo and cover blob IDs at publish time
  belongs_to :published_photo_blob, class_name: 'ActiveStorage::Blob', optional: true
  belongs_to :published_cover_blob, class_name: 'ActiveStorage::Blob', optional: true

  has_rich_text :body

  validates :subject, presence: true, length: { maximum: 255 }
  validate :body_cannot_be_empty

  default_scope { where(archived: false).order(published_at: :desc, updated_at: :desc) }
  scope :published, lambda {
                      where(archived: false).where.not(published_at: nil).order(published_at: :desc, updated_at: :desc)
                    }
  scope :archived, -> { where(archived: true).order(published_at: :desc, updated_at: :desc) }
  scope :publicly_listed, -> { where(visibility: :public) }
  scope :publicly_indexable, -> { where(visibility: %i[public unlisted]) }

  extend FriendlyId
  friendly_id :subject, use: %i[slugged history scoped], scope: :account

  before_destroy :remove_pinned_by
  after_save :remove_pinned_by, if: proc { archived? or visibility_hidden? }

  enum visibility: { public: 0, unlisted: 1, hidden: 2 }, _prefix: true, _default: :public

  def published?
    published_at.present?
  end

  def draft?
    !published?
  end

  def archive!
    self.archived = true
    save!
  end

  def description
    body.to_plain_text.truncate(255)
  end

  def send_newsletter
    raise 'Cannot send newsletter unless published' unless published?
    raise 'already sent' if finished_sending?

    PublishPostJob.perform_later self
    PingSearchEnginesJob.set(wait: 1.hour).perform_later account
  end

  def url(show_unverified: false)
    scheme = Rails.env.production? ? 'https' : 'http'
    port = Rails.env.production? ? nil : ':3000'
    domain_host = account.host(show_unverified: show_unverified)
    "#{scheme}://#{domain_host}#{port}/posts/#{slug}"
  end

  # Wabi-sabi mode: snapshot the current account photo and cover when publishing
  def snapshot_images!
    self.published_photo_blob = account.photo.blob if account.photo.attached?
    self.published_cover_blob = account.cover.blob if account.cover.attached?
  end

  # Get the appropriate photo for display based on wabi_sabi_mode
  # Returns an ActiveStorage attachment-like object or nil
  def display_photo
    return account.photo unless account.wabi_sabi_mode?
    return account.photo unless published_photo_blob.present?

    published_photo_blob
  end

  # Get the appropriate cover for display based on wabi_sabi_mode
  # Returns an ActiveStorage attachment-like object or nil
  def display_cover
    return account.cover unless account.wabi_sabi_mode?
    return account.cover unless published_cover_blob.present?

    published_cover_blob
  end

  # Check if display_photo returns a blob (historical) vs attachment (current)
  def display_photo_is_blob?
    account.wabi_sabi_mode? && published_photo_blob.present?
  end

  # Check if display_cover returns a blob (historical) vs attachment (current)
  def display_cover_is_blob?
    account.wabi_sabi_mode? && published_cover_blob.present?
  end

  private

  def body_cannot_be_empty
    errors.add(:body, "can't be empty") if body.blank?
  end

  def remove_pinned_by
    pinned_by&.update(pinned_post: nil)
  end
end
