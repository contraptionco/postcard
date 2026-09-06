# frozen_string_literal: true

require 'test_helper'

class UnsubscriptionControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:new_user)
    @subscription = @account.subscriptions.create!(
      email_address: EmailAddress.create!(email: 'unsubscribe@example.com'), source: :signup,
      verified_at: Time.current, verification_digest: Subscription.digest('old-token'),
      verification_created_at: Time.current
    )
    @message = EmailMessage.create!(account: @account, subscription: @subscription,
                                    user: @subscription.email_address, to: @subscription.email_address.email)
    host! @account.postcard_host
  end

  test 'unknown token is a friendly 404 for both display and unsubscribe' do
    get unsubscription_path('invalid-token')
    assert_response :not_found
    assert_select 'h1', 'This unsubscribe link is invalid'

    delete unsubscription_path(SecureRandom.uuid)
    assert_response :not_found
    assert_nil @subscription.reload.unsubscribed_at
  end

  test 'valid unsubscribe revokes confirmation token and repeated unsubscribe is safe' do
    get unsubscription_path(@message.unsubscribe_token)
    assert_response :success
    assert_select 'a', text: 'Unsubscribe'

    delete unsubscription_path(@message.unsubscribe_token)
    assert_response :see_other
    assert @message.reload.triggered_unsubscribe?
    assert @subscription.reload.unsubscribed_at
    assert_nil @subscription.verification_digest

    get unsubscription_path(@message.unsubscribe_token)
    assert_response :success
    assert_select 'h1', 'You are unsubscribed'
    assert_select 'a', text: 'Unsubscribe', count: 0

    delete unsubscription_path(@message.unsubscribe_token)
    assert_response :see_other
  end

  test 'email history with a deleted subscription still gives a safe unsubscribe response' do
    @subscription.delete
    get unsubscription_path(@message.unsubscribe_token)
    assert_response :success
    assert_select 'h1', 'You are unsubscribed'

    delete unsubscription_path(@message.unsubscribe_token)
    assert_response :see_other
    assert @message.reload.triggered_unsubscribe?
  end

  test 'an old newsletter unsubscribe link remains usable after tracking cleanup' do
    @message.update!(sent_at: 1.year.ago)

    CleanupTrackingDataJob.perform_now

    get unsubscription_path(@message.unsubscribe_token)
    assert_response :success
    assert_select 'a', text: 'Unsubscribe'
    delete unsubscription_path(@message.unsubscribe_token)
    assert_response :see_other
    assert @subscription.reload.unsubscribed_at
    assert @message.reload.triggered_unsubscribe?
  end
end
