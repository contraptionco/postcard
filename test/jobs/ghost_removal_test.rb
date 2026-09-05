# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GhostJobRemovalTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test 'persisted legacy email and name jobs complete without HTTP outside the test guard' do
    payload = persisted_payload('retired-reader@example.com', 'Retired Reader')

    assert_nil assert_retired_job_finishes_offline(payload)
  end

  test 'persisted account GlobalID jobs also complete without HTTP' do
    payload = persisted_payload(accounts(:new_user))

    assert_nil assert_retired_job_finishes_offline(payload)
  end

  test 'queued jobs for deleted accounts are discarded without HTTP or retry' do
    account = accounts(:new_user)
    payload = persisted_payload(account)
    account.destroy!

    discarded = []
    subscriber = ->(event) { discarded << event.payload }
    ActiveSupport::Notifications.subscribed(subscriber, 'discard.active_job') do
      assert_retired_job_finishes_offline(payload)
    end
    assert_equal 1, discarded.length
    assert_instance_of ActiveJob::DeserializationError, discarded.first[:error]
  end

  private

  def persisted_payload(*arguments)
    # Exercise the same argument serialization/deserialization used by a stored
    # queue row, including jobs written before the integration was removed.
    JSON.parse(SubscribeToContraptionGhostJob.new(*arguments).serialize.to_json)
  end

  def assert_retired_job_finishes_offline(payload)
    request = ->(*) { flunk 'A retired Ghost job must never open an HTTP connection' }
    result = nil
    Rails.env.stub(:test?, false) do
      Net::HTTP.stub(:start, request) do
        assert_no_enqueued_jobs do
          result = ActiveJob::Base.execute(payload)
        end
      end
    end
    result
  end
end
