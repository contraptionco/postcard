# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class AccountOauthTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test 'Google signup queues the account identity and skips newsletter sync once locked' do
    auth = OmniAuth::AuthHash.new(provider: 'google_oauth2', uid: 'synthetic-new-google-user',
      info: { email: 'google-signup@example.com', email_verified: true, name: 'Google Signup', image: nil })
    account = Truemail.stub(:valid?, true) { Account.from_omniauth(auth) }

    assert account.persisted?
    assert_enqueued_with(job: SubscribeToContraptionGhostJob, args: [account])
    account.update!(locked_at: Time.current)

    Net::HTTP.stub(:start, ->(*) { flunk 'Locked Google signups must not be sent to Ghost' }) do
      Rails.env.stub(:test?, false) do
        assert_performed_jobs 1, only: SubscribeToContraptionGhostJob do
          perform_enqueued_jobs(only: SubscribeToContraptionGhostJob)
        end
      end
    end
  end

  test 'invalid Google signup returns normally without serializing an unsaved account' do
    auth = OmniAuth::AuthHash.new(provider: 'google_oauth2', uid: 'synthetic-invalid-google-user',
      info: { email: 'invalid-email', email_verified: true, name: 'Invalid Signup', image: nil })

    assert_no_enqueued_jobs(only: SubscribeToContraptionGhostJob) do
      assert_nil Truemail.stub(:valid?, true) { Account.from_omniauth(auth) }
    end
  end
end
