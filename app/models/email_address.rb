# frozen_string_literal: true

class EmailAddress < ApplicationRecord
  has_many :messages, class_name: 'EmailMessage', as: :user, dependent: :destroy
  has_many :subscriptions, dependent: :destroy

  audited

  before_save :downcase_email

  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]{2,}\z/i
  validates :email, presence: true, length: { maximum: 255 },
                    format: { with: VALID_EMAIL_REGEX },
                    uniqueness: true

  private

  def downcase_email
    self.email = email.downcase
  end
end
