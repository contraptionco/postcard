# frozen_string_literal: true

require 'test_helper'

class CleanupTrackingDataJobTest < ActiveSupport::TestCase
  test 'retains old unfinished work and worker state while clearing only old finished jobs' do
    ready = old_job
    scheduled = old_job(scheduled_at: 1.day.from_now)
    scheduled.update_columns(scheduled_at: 3.weeks.ago)
    failed = old_job
    failed.ready_execution.destroy!
    failed.failed_with(IOError.new('Retry after the provider recovers'))
    claimed = old_job
    claimed.ready_execution.destroy!
    process = SolidQueue::Process.create!(kind: 'Worker', last_heartbeat_at: 3.weeks.ago,
                                          created_at: 3.weeks.ago, pid: 123, hostname: 'test')
    claimed.create_claimed_execution!(process: process)
    semaphore = SolidQueue::Semaphore.create!(key: 'old-worker-key', value: 0, expires_at: 3.weeks.ago,
                                              created_at: 3.weeks.ago, updated_at: 3.weeks.ago)
    old_finished = old_job
    old_finished.ready_execution.destroy!
    old_finished.update_columns(finished_at: 3.weeks.ago, updated_at: Time.current)
    recent_finished = old_job
    recent_finished.ready_execution.destroy!
    recent_finished.update_columns(finished_at: 1.day.ago)

    CleanupTrackingDataJob.perform_now

    [ready, scheduled, failed, claimed, recent_finished].each { |job| assert SolidQueue::Job.exists?(job.id) }
    assert SolidQueue::ReadyExecution.exists?(job_id: ready.id)
    assert SolidQueue::ScheduledExecution.exists?(job_id: scheduled.id)
    assert SolidQueue::FailedExecution.exists?(job_id: failed.id)
    assert SolidQueue::ClaimedExecution.exists?(job_id: claimed.id)
    assert SolidQueue::Process.exists?(process.id)
    assert SolidQueue::Semaphore.exists?(semaphore.id)
    refute SolidQueue::Job.exists?(old_finished.id)

    failed.reload.retry
    assert SolidQueue::ReadyExecution.exists?(job_id: failed.id), 'preserved failed jobs must remain retryable'
  end

  test 'finished queue retention uses the configured duration' do
    job = old_job
    job.ready_execution.destroy!
    job.update_columns(finished_at: 3.days.ago)

    CleanupTrackingDataJob.perform_now(retention_period: 1.week)
    assert SolidQueue::Job.exists?(job.id)
    CleanupTrackingDataJob.perform_now(retention_period: 2.days)
    refute SolidQueue::Job.exists?(job.id)
  end

  private

  def old_job(scheduled_at: Time.current)
    SolidQueue::Job.enqueue(AnalyticsSummaryEmailJob.new(accounts(:new_user)), scheduled_at: scheduled_at).tap do |job|
      job.update_columns(created_at: 3.weeks.ago, updated_at: 3.weeks.ago, scheduled_at: 3.weeks.ago)
    end
  end
end
