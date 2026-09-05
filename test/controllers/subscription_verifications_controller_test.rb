# frozen_string_literal: true

require 'test_helper'

class SubscriptionVerificationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @account = Rails.configuration.solo_mode ? Account.first : accounts(:new_user)
    @subscription = @account.subscriptions.create!(
      email_address: EmailAddress.create!(email: 'confirmation@example.com'), source: :signup,
      verification_digest: Subscription.digest('valid-token'), verification_created_at: Time.current
    )
    host! @account.host
  end

  test 'valid confirmation succeeds and repeated confirmation does not notify twice' do
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      2.times do
        get subscription_verification_path(@subscription), params: { token: 'valid-token' }
        assert_redirected_to '/'
        assert_equal 'Email verified!', flash[:notice]
      end
    end
  end

  test 'expired token gives a normal error without subscribing' do
    travel 3.days do
      get subscription_verification_path(@subscription), params: { token: 'valid-token' }
      assert_redirected_to '/'
      assert_equal 'Link expired - please sign up again', flash[:alert]
    end
    refute @subscription.reload.active?
  end
end
