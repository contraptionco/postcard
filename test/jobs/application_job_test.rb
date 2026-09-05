# frozen_string_literal: true

require 'test_helper'

class ApplicationJobTest < ActiveSupport::TestCase
  test 'a queued job for a deleted account is discarded during deserialization' do
    account = accounts(:new_user)
    payload = AnalyticsSummaryEmailJob.new(account).serialize
    account.destroy!

    assert_nothing_raised { ActiveJob::Base.execute(payload) }
  end
end
