# frozen_string_literal: true

require 'test_helper'

class DestroyAccountJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:new_user)
  end

  test 'deletes the account and bulk-deletable associated data' do
    visit = @account.visits.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                                    started_at: Time.current)
    visit.events.create!(name: 'autotrack', time: Time.current, user_id: @account.id,
                         properties: { controller: 'pages' })

    # A page view recorded for an anonymous visitor to the account's page
    visitor_visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                                        started_at: Time.current)
    visitor_event = visitor_visit.events.create!(name: 'autotrack', time: Time.current,
                                                 properties: { account: @account.id, controller: 'public_pages' })

    email_address = EmailAddress.create!(email: 'subscriber@example.com')
    @account.subscriptions.create!(email_address: email_address, source: :signup, verified_at: Time.current)
    @account.messages.create!(to: 'subscriber@example.com')

    DestroyAccountJob.perform_now(@account)

    assert_not Account.exists?(@account.id)
    assert_not Ahoy::Visit.exists?(visit.id)
    assert_not Ahoy::Event.exists?(visitor_event.id)
    assert_equal 0, Ahoy::Event.where(user_id: @account.id).count
    assert_equal 0, Subscription.where(account_id: @account.id).count
    assert_equal 0, EmailMessage.where(user: @account).count
    assert_equal 0, Audited::Audit.where(auditable_type: 'Account', auditable_id: @account.id).count
    assert EmailAddress.exists?(email_address.id), 'shared email addresses should not be deleted'
  end
end
