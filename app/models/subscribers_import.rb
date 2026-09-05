# frozen_string_literal: true

class SubscribersImport < ApplicationRecord
  belongs_to :account

  has_many :subscriptions, dependent: :nullify
  has_one_attached :file, dependent: :destroy

  validates :file, presence: true
  validates :sources_description, presence: true
  after_update :import, if: :saved_change_to_approved?
  after_create_commit :handle_import_creation

  def emails
    @emails ||= file.open do |f|
      emails = []
      CSV.parse(f.read, headers: false).each do |row|
        row.each do |cell|
          cell_cleaned = cell.to_s.strip.downcase
          emails.push(cell_cleaned) if EmailAddress::VALID_EMAIL_REGEX.match?(cell_cleaned)
        end
      end
      emails.uniq
    end
  end

  delegate :count, to: :emails, prefix: true

  private

  def handle_import_creation
    if Rails.configuration.solo_mode
      # In solo mode, auto-approve and process immediately
      update!(approved: true)
    else
      # In multi-user mode, send admin notification
      AdminMailer.new_subscribers_import_request(self).deliver_later
    end
  end

  def import
    return unless approved?

    SubscribersImportJob.perform_later(self)
    AccountMailer.subscribers_import_approved(self).deliver_later
  end
end
