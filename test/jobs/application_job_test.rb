# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class ApplicationJobTest < ActiveSupport::TestCase
  test 'a queued job for a deleted account is discarded during deserialization' do
    account = accounts(:new_user)
    payload = AnalyticsSummaryEmailJob.new(account).serialize
    account.destroy!

    assert_nothing_raised { ActiveJob::Base.execute(payload) }
  end

  test 'transient GlobalID lookup failures remain failed for ordinary and deletion jobs' do
    [AnalyticsSummaryEmailJob, DestroyAccountJob].each do |job_class|
      payload = job_class.new(accounts(:new_user)).serialize
      lookup = ->(*) { raise ActiveRecord::ConnectionNotEstablished, 'temporary database outage' }

      GlobalID::Locator.stub(:locate, lookup) do
        error = assert_raises(ActiveJob::DeserializationError) { ActiveJob::Base.execute(payload) }
        assert_instance_of ActiveRecord::ConnectionNotEstablished, error.cause
      end
    end
  end
end
