# frozen_string_literal: true

class SubscribersImportJob < ApplicationJob
  def perform(*subscribers_imports)
    subscribers_imports.each.map(&method(:import))
  end

  private

  def import(subscribers_import)
    return unless subscribers_import.reload.approved?

    subscribers_import.emails.each do |email|
      account = subscribers_import.account
      email_address = EmailAddress.find_or_create_by(email: email)

      Subscription.create_with(source: :import, subscribers_import: subscribers_import, verified_at: Time.zone.now) \
                  .find_or_create_by(email_address: email_address,
                                     account: account)
    end
  end
end
