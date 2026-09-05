# frozen_string_literal: true

require 'test_helper'

class GhostSubscriptionVerificationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @account = Rails.configuration.solo_mode ? Account.first : accounts(:grandfathered_user)
    @subscription = @account.subscriptions.create!(
      email_address: EmailAddress.create!(email: 'ghost-reader@example.com'), source: :signup,
      verification_digest: Subscription.digest('valid-token'), verification_created_at: Time.current
    )
    host! @account.host
  end

  test 'opted-out account verifies normally without sharing its reader with Ghost' do
    assert_no_enqueued_jobs only: SubscribeToContraptionGhostJob do
      verify_link
    end
    assert @subscription.reload.active?
  end

  test 'enabled account queues only its confirmed reader once even when the link is reopened later' do
    @account.update!(sync_to_ghost: true)
    assert_enqueued_with job: SubscribeToContraptionGhostJob, args: ['ghost-reader@example.com'] do
      verify_link
    end
    original_verified_at = @subscription.reload.verified_at
    travel 1.hour do
      assert_no_enqueued_jobs do
        verify_link
      end
    end
    assert_equal original_verified_at, @subscription.reload.verified_at
  end

  test 'invalid and expired links never enqueue the integration or verify the subscription' do
    @account.update!(sync_to_ghost: true)
    assert_no_enqueued_jobs do
      verify_link(token: 'incorrect', successful: false)
      verify_link(token: nil, successful: false)
      travel 3.days do
        verify_link(successful: false)
      end
    end
    refute @subscription.reload.active?
  end

  test 'email unsubscribe route revokes old verification links without reactivating or sharing the reader' do
    @account.update!(sync_to_ghost: true)
    verify_link
    original_verified_at = @subscription.reload.verified_at
    message = EmailMessage.create!(account: @account, subscription: @subscription,
                                   to: @subscription.email_address.email)
    unsubscribe_path = unsubscription_path(message.unsubscribe_token)

    get unsubscribe_path
    assert_response :success
    assert_select 'a[href=?][data-turbo-method="delete"]', unsubscribe_path

    assert_no_enqueued_jobs do
      delete unsubscribe_path
      assert_response :see_other
      assert_redirected_to '/'
      assert_equal 'You have unsubscribed!', flash[:notice]

      travel 1.hour do
        verify_link(successful: false)
      end
    end

    assert message.reload.triggered_unsubscribe?
    assert @subscription.reload.unsubscribed_at
    refute @subscription.active?
    assert_nil @subscription.verification_digest
    assert_nil @subscription.verification_created_at
    assert_equal original_verified_at, @subscription.verified_at
  end

  test 'changing the account slug preserves the opt-in and its destination' do
    @account.update!(sync_to_ghost: true, slug: 'renamed-operator')
    host! @account.host
    assert_enqueued_with job: SubscribeToContraptionGhostJob, args: ['ghost-reader@example.com'] do
      verify_link
    end
  end

  private

  def verify_link(token: 'valid-token', successful: true)
    get subscription_verification_path(@subscription), params: { token: token }
    assert_redirected_to '/'
    assert_equal successful ? 'Email verified!' : 'Link expired - please sign up again', flash[successful ? :notice : :alert]
  end
end
