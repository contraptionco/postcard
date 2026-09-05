# frozen_string_literal: true

require 'test_helper'

class SubscriberExportAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:grandfathered_user)
    @other_account = accounts(:new_user)
    subscribe(@account, 'own-reader@example.com')
    subscribe(@other_account, 'other-reader@example.com')
    host! Rails.configuration.base_host
  end

  test 'guests cannot export subscriber email addresses' do
    get page_subscribers_export_path(@account, format: :csv)

    assert_response :unauthorized
    assert_not_includes response.body, 'own-reader@example.com'
    assert_not_includes response.body, 'other-reader@example.com'
  end

  test 'an author can download their own export with attachment headers and no other account data' do
    sign_in @account
    get page_subscribers_export_path(@account, format: :csv)

    assert_response :success
    assert_equal 'text/csv', response.media_type
    assert_match(/attachment; filename=#{@account.slug}-subscribers-.*\.csv/, response.headers['Content-Disposition'])
    assert_includes response.body, 'own-reader@example.com'
    assert_not_includes response.body, 'other-reader@example.com'
  end

  test 'an author cannot export another author’s subscribers or override ownership through parameters' do
    sign_in @account
    get page_subscribers_export_path(@other_account, format: :csv), params: { account_id: @account.id }

    assert_redirected_to page_path(@account)
    assert_not_includes response.body, 'other-reader@example.com'
    assert_nil response.headers['Content-Disposition']
  end

  test 'an admin can export the selected author without mixing subscriber accounts' do
    @account.update!(admin: true)
    sign_in @account
    get page_subscribers_export_path(@other_account, format: :csv)

    assert_response :success
    assert_includes response.headers['Content-Disposition'], "#{@other_account.slug}-subscribers-"
    assert_includes response.body, 'other-reader@example.com'
    assert_not_includes response.body, 'own-reader@example.com'
  end

  private

  def subscribe(account, email)
    account.subscriptions.create!(email_address: EmailAddress.create!(email: email), source: :signup,
                                  verified_at: 1.day.ago)
  end
end
