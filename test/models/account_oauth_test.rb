# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class AccountOauthTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test 'invalid Google signup returns normally without serializing an unsaved account' do
    auth = OmniAuth::AuthHash.new(provider: 'google_oauth2', uid: 'synthetic-invalid-google-user',
      info: { email: 'invalid-email', email_verified: true, name: 'Invalid Signup', image: nil })

    assert_no_enqueued_jobs(only: SubscribeToContraptionGhostJob) do
      assert_nil Truemail.stub(:valid?, true) { Account.from_omniauth(auth) }
    end
  end
end
