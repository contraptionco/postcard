# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GhostOauthRemovalTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  teardown do
    @created_account&.cover&.purge if @created_account&.cover&.attached?
  end

  test 'Google account creation preserves local updates subscriptions without Ghost' do
    updates = accounts(:grandfathered_user)
    updates.update_columns(slug: 'updates')
    auth = OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'ghost-removal-google-user',
      info: { email: 'google-author@example.com', email_verified: true, name: 'Google Author', image: nil }
    )

    assert_difference 'Account.count', 1 do
      assert_no_enqueued_jobs only: SubscribeToContraptionGhostJob do
        @created_account = Truemail.stub(:valid?, true) { Account.from_omniauth(auth) }
      end
    end

    assert @created_account.persisted?
    assert_equal 'google-author@example.com', @created_account.email
    assert_equal 'Google Author', @created_account.name
    assert updates.subscriptions.active.joins(:email_address).exists?(email_addresses: { email: @created_account.email })
  end
end
