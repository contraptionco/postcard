# frozen_string_literal: true

require 'test_helper'

class DestroyAccountJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:new_user)
  end

  test 'deletes the account and bulk-deletable associated data' do
    visit = @account.visits.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                                    started_at: Time.current)
    visit.events.create!(name: 'autotrack', time: Time.current, user_id: @account.id,
                         properties: { controller: 'pages' })

    # A page view recorded for an anonymous visitor to the account's page
    visitor_visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                                        started_at: Time.current)
    visitor_event = visitor_visit.events.create!(name: 'autotrack', time: Time.current,
                                                 properties: { account: @account.id, controller: 'public_pages' })

    email_address = EmailAddress.create!(email: 'subscriber@example.com')
    @account.subscriptions.create!(email_address: email_address, source: :signup, verified_at: Time.current)
    @account.messages.create!(to: 'subscriber@example.com')

    DestroyAccountJob.perform_now(@account)

    assert_not Account.exists?(@account.id)
    assert_not Ahoy::Visit.exists?(visit.id)
    assert_not Ahoy::Event.exists?(visitor_event.id)
    assert_equal 0, Ahoy::Event.where(user_id: @account.id).count
    assert_equal 0, Subscription.where(account_id: @account.id).count
    assert_equal 0, EmailMessage.where(user: @account).count
    assert_equal 0, Audited::Audit.where(auditable_type: 'Account', auditable_id: @account.id).count
    assert EmailAddress.exists?(email_address.id), 'shared email addresses should not be deleted'
  end

  test 'deletes recipient email history and archived posts while preserving shared recipient data' do
    recipient = EmailAddress.create!(email: 'shared-recipient@example.com')
    subscription = @account.subscriptions.create!(email_address: recipient, source: :signup)
    message = EmailMessage.create!(account: @account, user: recipient, subscription: subscription,
                                    to: recipient.email, subject: 'Private deleted-account history')
    other_account = accounts(:grandfathered_user)
    other_message = EmailMessage.create!(account: other_account, user: recipient, to: recipient.email)
    archived_post = @account.posts.create!(subject: 'Archived post', body: 'Archived content', archived: true)

    DestroyAccountJob.perform_now(@account)

    refute EmailMessage.exists?(message.id)
    refute Post.unscoped.exists?(archived_post.id)
    assert EmailMessage.exists?(other_message.id)
    assert EmailAddress.exists?(recipient.id)
    assert Account.exists?(other_account.id)
  end

  test 'cancels pending account jobs but preserves unrelated shared and running jobs' do
    post = @account.posts.create!(subject: 'Scheduled post', body: 'Post body')
    other_account = accounts(:grandfathered_user)
    pending = SolidQueue::Job.enqueue(AnalyticsSummaryEmailJob.new(@account), scheduled_at: 1.day.from_now)
    post_job = SolidQueue::Job.enqueue(PublishPostJob.new(post), scheduled_at: 1.day.from_now)
    unrelated = SolidQueue::Job.enqueue(AnalyticsSummaryEmailJob.new(other_account), scheduled_at: 1.day.from_now)
    shared = SolidQueue::Job.enqueue(AnalyticsSummaryEmailJob.new(@account, other_account), scheduled_at: 1.day.from_now)
    running = SolidQueue::Job.enqueue(AnalyticsSummaryEmailJob.new(@account))
    running.ready_execution.destroy!
    process = SolidQueue::Process.create!(kind: "Worker", last_heartbeat_at: Time.current, pid: 123, hostname: "test")
    running.create_claimed_execution!(process: process)
    destroyer = DestroyAccountJob.new(@account)
    current_job = SolidQueue::Job.enqueue(destroyer)

    destroyer.perform_now

    refute SolidQueue::Job.exists?(pending.id)
    refute SolidQueue::ScheduledExecution.exists?(job_id: pending.id)
    refute SolidQueue::Job.exists?(post_job.id)
    [unrelated, shared, running, current_job].each { |job| assert SolidQueue::Job.exists?(job.id) }
  end

end
