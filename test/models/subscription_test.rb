# frozen_string_literal: true

require 'test_helper'

class SubscriptionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @token = 'valid-verification-token'
    @subscription = accounts(:new_user).subscriptions.create!(
      email_address: EmailAddress.create!(email: 'verification@example.com'), source: :signup,
      verification_digest: Subscription.digest(@token), verification_created_at: Time.current
    )
  end

  test 'stale subscription copies verify once and preserve the original verification time' do
    other_request = Subscription.find(@subscription.id)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      assert @subscription.verify!(token: @token)
      verified_at = @subscription.reload.verified_at
      travel 1.hour do
        assert other_request.verify!(token: @token)
        assert_equal verified_at, other_request.reload.verified_at
      end
    end
  end

  test 'missing incorrect expired and malformed verification tokens fail without notifications' do
    assert_no_enqueued_jobs do
      refute @subscription.verify!(token: nil)
      refute @subscription.verify!(token: 'incorrect')
      travel 3.days do
        refute @subscription.verify!(token: @token)
      end
      @subscription.update!(verification_digest: 'invalid digest')
      refute @subscription.verify!(token: @token)
    end
    assert_nil @subscription.reload.verified_at
  end

  test 'unsubscribe revokes verification even for a stale in-flight request' do
    assert @subscription.verify!(token: @token)
    in_flight_request = Subscription.find(@subscription.id)
    @subscription.unsubscribe!

    refute in_flight_request.verify!(token: @token)
    assert @subscription.reload.unsubscribed_at
    assert_nil @subscription.verification_digest
    assert_nil @subscription.verification_created_at
  end

  test 'fresh confirmation can reactivate a removed subscription without a duplicate owner notification' do
    assert @subscription.verify!(token: @token)
    @subscription.unsubscribe!
    @subscription.update!(verification_digest: Subscription.digest('fresh'), verification_created_at: Time.current)

    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      assert @subscription.verify!(token: 'fresh')
    end
    assert @subscription.reload.active?
  end
end
