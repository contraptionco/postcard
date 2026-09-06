# frozen_string_literal: true

class Post < ApplicationRecord
  audited associated_with: :account

  belongs_to :account, touch: true

  has_one :pinned_by, class_name: 'Account', inverse_of: :pinned_post, dependent: :nullify, foreign_key: :pinned_post_id

  has_many :email_messages, dependent: :destroy

  has_rich_text :body

  # Presence validations only apply when publishing (not in :draft context)
  validates :subject, presence: true, unless: :draft_context?
  validates :subject, length: { maximum: 255 }
  validate :body_cannot_be_empty, unless: :draft_context?

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

  enum :visibility, { public: 0, unlisted: 1, hidden: 2 }, prefix: true, default: :public

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

  private

  def body_cannot_be_empty
    errors.add(:body, "can't be empty") if body.blank?
  end

  def draft_context?
    validation_context == :draft
  end

  def remove_pinned_by
    pinned_by&.update(pinned_post: nil)
  end
end
