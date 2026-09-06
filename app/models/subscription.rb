# frozen_string_literal: true

class Subscription < ApplicationRecord
  audited associated_with: :account

  belongs_to :account
  belongs_to :email_address
  belongs_to :subscribers_import, optional: true
  visitable :ahoy_subscription_visit
  scope :active, -> { where(unsubscribed_at: nil).where.not(verified_at: nil).order(verified_at: :desc) }
  scope :export, -> { where.not(verified_at: nil).order(created_at: :asc) }

  attr_accessor :verification_token

  enum source: { signup: 0, invite: 1, import: 2 }, _prefix: true
  validates :source, presence: true

  def active?
    !!verified_at && !unsubscribed_at
  end

  def unsubscribe!
    update!(unsubscribed_at: Time.current, verification_digest: nil, verification_created_at: nil)
    self.verification_token = nil
  end

  def self.digest(string)
    cost = if ActiveModel::SecurePassword.min_cost
             BCrypt::Engine::MIN_COST
           else
             BCrypt::Engine.cost
           end
    BCrypt::Password.create(string, cost: cost)
  end

  def valid_verification_token?(token)
    return false if verification_digest.nil?

    BCrypt::Password.new(verification_digest).is_password?(token)
  end

  def self.new_token
    SecureRandom.urlsafe_base64
  end

  def verify!
    already_verified = verified_at.present?
    self.verified_at = Time.zone.now
    self.unsubscribed_at = nil
    save!

    send_new_subscriber_notification unless already_verified
  end

  # Sends verification email.
  def send_verification_email
    create_verification_digest if verification_token.blank?

    AccountMailer.subscription_verification(self).deliver_now
  end

  private

  def create_verification_digest
    self.verification_token = Subscription.new_token
    self.verification_digest = Subscription.digest(verification_token)
    self.verification_created_at = Time.zone.now
    save
  end

  def send_new_subscriber_notification
    return unless verified_at.present? && unsubscribed_at.blank?
    return unless source_signup? || source_invite?

    PostInAdminChatJob.perform_later "[New subscriber - #{self.account.host}] #{self.email_address.email}"
    AccountMailer.new_subscriber(self).deliver_later
  end
end
