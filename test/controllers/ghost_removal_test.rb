# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GhostRemovalTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    host! Rails.configuration.base_host
  end

  teardown do
    @created_account&.cover&.purge if @created_account&.cover&.attached?
  end

  test 'signup offers account creation without the external newsletter opt-in' do
    prepare_signup

    get new_account_registration_path

    assert_response :success
    assert_select 'input[name="account[email]"]', count: 1
    assert_select 'input[name="account[password]"]', count: 1
    assert_select '[name="account[subscribe_to_newsletter]"]', count: 0
    assert_not_includes response.body, 'Subscribe to updates from'
  end

  test 'an old signup form can still create an account without enqueuing Ghost' do
    prepare_signup

    assert_difference 'Account.count', 1 do
      assert_no_enqueued_jobs only: SubscribeToContraptionGhostJob do
        Truemail.stub(:valid?, true) do
          post account_registration_path, params: {
            account: {
              name: 'New Postcard Author', email: 'new-author@example.com',
              password: 'password123', subscribe_to_newsletter: '1'
            }
          }
        end
      end
    end

    @created_account = Account.find_by!(email: 'new-author@example.com')
    assert_equal 'New Postcard Author', @created_account.name
    assert @created_account.valid_password?('password123')
    expected_path = Rails.configuration.solo_mode ? page_path(@created_account) : page_checkout_path(@created_account)
    assert_redirected_to expected_path
  end

  test 'the legacy featured author still verifies local newsletter subscriptions without Ghost' do
    account = Rails.configuration.solo_mode ? Account.first : accounts(:grandfathered_user)
    account.update!(slug: 'philipithomas')
    subscription = account.subscriptions.create!(
      email_address: EmailAddress.create!(email: 'local-newsletter-reader@example.com'), source: :signup,
      verification_digest: Subscription.digest('local-newsletter-token'), verification_created_at: Time.current
    )
    host! account.host

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      assert_no_enqueued_jobs only: SubscribeToContraptionGhostJob do
        get subscription_verification_path(subscription), params: { token: 'local-newsletter-token' }
      end
    end

    assert_redirected_to '/'
    assert_equal 'Email verified!', flash[:notice]
    assert subscription.reload.active?
    assert_equal account.id, subscription.account_id
  end

  private

  def prepare_signup
    # SOLO accepts only its first account. Use the real route configuration and
    # remove only transactional fixtures instead of changing the app mode.
    Account.find_each(&:destroy!) if Rails.configuration.solo_mode
  end
end
