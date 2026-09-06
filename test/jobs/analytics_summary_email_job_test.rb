# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class AnalyticsSummaryEmailJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @deleted_account = accounts(:new_user)
    @live_account = accounts(:grandfathered_user)
    @live_account.subscribe(AccountMailer::ANALYTICS_SUMMARY_LIST)
    2.times do
      visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                                  started_at: Time.current)
      visit.events.create!(name: 'autotrack', time: Time.current, properties: {
        account: @live_account.id, domain: @live_account.postcard_host, canonical_url: @live_account.url,
        controller: 'public_pages', action: 'show'
      })
    end
  end

  %w[first last].each do |position|
    test "a persisted mixed-account batch still delivers to its live account when the #{position} record is deleted" do
      accounts = position == 'first' ? [@deleted_account, @live_account] : [@live_account, @deleted_account]
      queued = SolidQueue::Job.enqueue(AnalyticsSummaryEmailJob.new(*accounts), scheduled_at: 1.day.from_now)

      DestroyAccountJob.perform_now(@deleted_account)

      assert SolidQueue::Job.exists?(queued.id), 'Deletion must preserve the other account’s queued work'
      assert_emails 1 do
        ActiveJob::Base.execute(queued.reload.arguments)
      end
      assert_equal [@live_account.email], ActionMailer::Base.deliveries.last.to
      assert_match '2 people visited', ActionMailer::Base.deliveries.last.subject
      assert_equal 1, EmailMessage.where(user: @live_account).count
    end
  end

  test 'a database failure after a missing record keeps the remaining work failed and retryable' do
    payload = AnalyticsSummaryEmailJob.new(@deleted_account, @live_account).serialize
    @deleted_account.destroy!
    original_lookup = GlobalID::Locator.method(:locate)
    lookup = lambda do |reference, *options|
      if GlobalID.parse(reference).model_id == @live_account.id.to_s
        raise ActiveRecord::ConnectionNotEstablished, 'temporary database outage'
      end

      original_lookup.call(reference, *options)
    end

    assert_emails 0 do
      GlobalID::Locator.stub(:locate, lookup) do
        error = assert_raises(ActiveJob::DeserializationError) { ActiveJob::Base.execute(payload) }
        assert_instance_of ActiveRecord::ConnectionNotEstablished, error.cause
      end
    end
  end

  test 'the weekly scheduler enqueues each account independently' do
    travel_to Time.utc(2026, 9, 7, 12) do
      assert_enqueued_jobs 2, only: AnalyticsSummaryEmailJob do
        EnqueueAnalyticsSummaryEmailsJob.perform_now
      end
      [@deleted_account, @live_account].each do |account|
        assert_enqueued_with(job: AnalyticsSummaryEmailJob, args: [account])
      end
    end
  end
end
