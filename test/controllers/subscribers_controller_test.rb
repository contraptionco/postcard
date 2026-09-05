# frozen_string_literal: true

require 'test_helper'
require 'csv'

class SubscribersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:grandfathered_user)
    @other_account = accounts(:new_user)
    host! Rails.configuration.base_host
    sign_in @account
  end

  test 'paginates the active list while keeping the full subscriber count' do
    51.times { |index| create_subscription("reader#{index}@example.com") }
    create_subscription('unverified@example.com', verified_at: nil)
    create_subscription('removed@example.com', unsubscribed_at: Time.current)
    create_subscription('another-account@example.com', account: @other_account)

    get page_subscribers_path(@account)

    assert_response :success
    assert_select 'h1', text: '51 subscribers'
    assert_select 'tbody tr', count: 50
    assert_select 'a[rel="next"]'
    assert_no_match 'unverified@example.com', response.body
    assert_no_match 'removed@example.com', response.body
    assert_no_match 'another-account@example.com', response.body

    get page_subscribers_path(@account), params: { page: 2 }

    assert_select 'h1', text: '51 subscribers'
    assert_select 'tbody tr', count: 1
    assert_select 'a[rel="prev"]'
    assert_select 'a[rel="next"]', count: 0
  end

  test 'search is case insensitive literal and scoped to active subscribers on this account' do
    create_subscription('first_name@example.com')
    create_subscription('firstname@example.com')
    create_subscription('other_first_name@example.com', account: @other_account)
    create_subscription('removed_first_name@example.com', unsubscribed_at: Time.current)

    get page_subscribers_path(@account), params: { q: ' FIRST_NAME ' }

    assert_response :success
    assert_select 'h1', text: '2 subscribers'
    assert_select 'tbody tr', count: 1
    assert_match 'first_name@example.com', response.body
    assert_no_match 'other_first_name@example.com', response.body
    assert_no_match 'removed_first_name@example.com', response.body
  end

  test 'empty searches show a clear result and preserve the overall count' do
    create_subscription('reader@example.com')

    get page_subscribers_path(@account), params: { q: '%' }

    assert_response :success
    assert_select 'h1', text: '1 subscriber'
    assert_match 'No subscribers match your search.', response.body
    assert_select 'tbody tr', count: 0
    assert_select 'a', text: 'Clear'
  end

  test 'pagination clamps invalid and out of range pages and preserves search' do
    51.times { |index| create_subscription("reader#{index}@example.com") }

    get page_subscribers_path(@account), params: { q: 'reader', page: -10 }

    assert_response :success
    assert_select 'tbody tr', count: 50
    assert_select 'a[rel="next"][href=?]', page_subscribers_path(@account, q: 'reader', page: 2)

    get page_subscribers_path(@account), params: { q: 'reader', page: 100_000 }

    assert_response :success
    assert_select 'tbody tr', count: 1
    assert_match 'Page 2 of 2', response.body
  end

  test 'CSV exports the complete verified list independent of search and pagination' do
    51.times { |index| create_subscription("reader#{index}@example.com") }
    create_subscription('removed@example.com', unsubscribed_at: Time.current)
    create_subscription('unverified@example.com', verified_at: nil)
    create_subscription('another-account@example.com', account: @other_account)

    get page_subscribers_export_path(@account, format: :csv), params: { q: 'reader0', page: 2 }

    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal ['Email', 'Verified at', 'Unsubscribed at', 'Source'], rows.headers
    assert_equal 52, rows.length
    emails = rows.map { |row| row['Email'] }
    assert_includes emails, 'removed@example.com'
    assert_includes emails, 'reader50@example.com'
    refute_includes emails, 'unverified@example.com'
    refute_includes emails, 'another-account@example.com'
  end

  test 'subscriber page preloads email addresses instead of querying once per row' do
    8.times { |index| create_subscription("reader#{index}@example.com") }
    email_queries = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql]
      email_queries << sql if sql.match?(/\ASELECT .*FROM "email_addresses"/m)
    end

    get page_subscribers_path(@account)

    assert_response :success
    assert_select 'tbody tr', count: 8
    assert_operator email_queries.length, :<=, 1
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test 'removing a subscriber preserves their email and subscription to another account' do
    subscription = create_subscription('reader@example.com')
    other_subscription = create_subscription('reader@example.com', account: @other_account)

    assert_no_difference ['EmailAddress.count', 'Subscription.count'] do
      delete page_subscriber_path(@account, subscription), params: { q: 'reader', page: 2 }
    end

    assert_redirected_to page_subscribers_path(@account, q: 'reader', page: 2)
    refute subscription.reload.active?
    assert other_subscription.reload.active?
    assert EmailAddress.exists?(subscription.email_address_id)
  end

  test 'removal requires a new email verification before resubscribing' do
    subscription = create_subscription('reader@example.com', verification_digest: Subscription.digest('old-link'),
                                                               verification_created_at: Time.current)

    delete page_subscriber_path(@account, subscription)

    subscription.reload
    assert_nil subscription.verification_digest
    assert_nil subscription.verification_created_at
    refute subscription.valid_verification_token?('old-link')
    refute subscription.active?

    subscription.send_verification_email

    assert subscription.valid_verification_token?(subscription.verification_token)
    refute subscription.active?
    subscription.verify!
    assert subscription.active?
  end

  test 'cannot remove another account subscriber through own account path' do
    subscription = create_subscription('reader@example.com', account: @other_account)

    assert_raises ActiveRecord::RecordNotFound do
      delete page_subscriber_path(@account, subscription)
    end

    assert subscription.reload.active?
  end

  test 'cannot view or change another account subscribers without admin access' do
    subscription = create_subscription('reader@example.com', account: @other_account)

    get page_subscribers_path(@other_account)
    assert_redirected_to page_path(@account)

    delete page_subscriber_path(@other_account, subscription)
    assert_redirected_to page_path(@account)
    assert subscription.reload.active?
  end

  test 'admin can manage another account subscribers' do
    @account.update!(admin: true)
    subscription = create_subscription('reader@example.com', account: @other_account)

    get page_subscribers_path(@other_account)
    assert_response :success
    assert_match 'reader@example.com', response.body

    delete page_subscriber_path(@other_account, subscription)
    assert_redirected_to page_subscribers_path(@other_account)
    refute subscription.reload.active?
  end

  test 'subscriber management requires authentication' do
    subscription = create_subscription('reader@example.com')
    sign_out @account

    get page_subscribers_path(@account)
    assert_response :redirect
    assert_match %r{/accounts/sign_in\z}, response.location

    delete page_subscriber_path(@account, subscription)
    assert_response :redirect
    assert_match %r{/accounts/sign_in\z}, response.location
    assert subscription.reload.active?
  end

  private

  def create_subscription(email, account: @account, **attributes)
    email_address = EmailAddress.find_or_create_by!(email: email)
    account.subscriptions.create!({ email_address: email_address, source: :signup, verified_at: Time.current }.merge(attributes))
  end
end
