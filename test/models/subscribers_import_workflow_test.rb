# frozen_string_literal: true

require 'test_helper'

class SubscribersImportWorkflowTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:grandfathered_user)
    @imports = []
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    @imports.each { |import| import.file.purge if import.file.attached? }
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test 'CSV extracts addresses from every column, normalizes case and whitespace, and deduplicates' do
    import = build_import("Name,Email,Other\nAlice, ALICE@EXAMPLE.COM ,not-an-address\nBob,bob@example.com,alice@example.com\n,,\n")

    assert_equal %w[alice@example.com bob@example.com], import.emails
    assert_equal 2, import.emails_count
  end

  test 'creating an import persists the mode-specific approval and queues the appropriate workflow' do
    import = nil
    assert_no_difference('Subscription.count') do
      import = build_import("new-reader@example.com\n")
    end

    if Rails.configuration.solo_mode
      assert import.reload.approved?
      assert_enqueued_with(job: SubscribersImportJob, args: [import])
      assert_enqueued_email_with AccountMailer, :subscribers_import_approved, args: [import]
      assert_not enqueued_jobs.any? { |job| job[:args].first == 'AdminMailer' }
    else
      assert_not import.reload.approved?
      assert_no_enqueued_jobs(only: SubscribersImportJob)
      assert_enqueued_email_with AdminMailer, :new_subscribers_import_request, args: [import]
      assert_not enqueued_jobs.any? { |job| job[:args].first == 'AccountMailer' }
    end
  end

  test 'approval queues once and unrelated edits or revocation do not enqueue another import' do
    import = build_import("new-reader@example.com\n")
    import.update_column(:approved, false)
    clear_enqueued_jobs

    assert_enqueued_jobs 1, only: SubscribersImportJob do
      import.update!(approved: true)
    end
    assert_enqueued_email_with AccountMailer, :subscribers_import_approved, args: [import]
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      import.update!(sources_description: 'Corrected source description')
      import.update!(approved: true)
      import.update!(approved: false)
    end
    assert_not import.reload.approved?
  end

  test 'serialized import job ignores approval revoked after enqueue' do
    import = build_import("revoked-reader@example.com\n")
    import.update_column(:approved, true)
    job = SubscribersImportJob.perform_later(import)
    import.update!(approved: false)

    assert_no_difference(['Subscription.count', 'EmailAddress.count']) do
      SubscribersImportJob.execute(job.serialize)
    end
  end

  test 'unapproved imports never create subscribers even when passed directly to the job' do
    import = build_import("pending-reader@example.com\n")
    import.update_column(:approved, false)

    assert_no_difference(['Subscription.count', 'EmailAddress.count']) do
      SubscribersImportJob.perform_now(import)
    end
  end

  test 'repeated imports preserve existing membership status and create only new account memberships' do
    active = subscribe(@account, 'active@example.com', verified_at: 3.days.ago)
    unverified = subscribe(@account, 'unverified@example.com')
    unsubscribed = subscribe(@account, 'unsubscribed@example.com', verified_at: 3.days.ago, unsubscribed_at: 2.days.ago)
    foreign = subscribe(accounts(:new_user), 'shared@example.com', verified_at: 3.days.ago, unsubscribed_at: 2.days.ago)
    originals = [active, unverified, unsubscribed, foreign].to_h { |subscription| [subscription.id, subscription.reload.attributes] }
    import = build_import("active@example.com,unverified@example.com,unsubscribed@example.com,shared@example.com,new@example.com\n")
    import.update_column(:approved, true)
    clear_enqueued_jobs

    assert_difference('Subscription.count', 2) do
      assert_difference('EmailAddress.count', 1) do
        SubscribersImportJob.perform_now(import)
      end
    end
    assert_no_difference(['Subscription.count', 'EmailAddress.count']) do
      SubscribersImportJob.perform_now(import.reload)
    end

    originals.each { |id, attributes| assert_equal attributes, Subscription.find(id).attributes }
    imported = @account.subscriptions.where(subscribers_import: import)
    assert_equal %w[new@example.com shared@example.com], imported.joins(:email_address).pluck('email_addresses.email').sort
    assert imported.all?(&:active?)
    assert imported.all?(&:source_import?)
    assert_equal foreign.email_address_id, imported.joins(:email_address).find_by!(email_addresses: { email: 'shared@example.com' }).email_address_id
    assert_no_enqueued_jobs
  end

  private

  def build_import(csv)
    import = @account.subscribers_imports.new(sources_description: 'Readers explicitly opted in on the previous site')
    import.file.attach(io: StringIO.new(csv), filename: 'subscribers.csv', content_type: 'text/csv')
    @imports << import
    import.save!
    import
  end

  def subscribe(account, email, **attributes)
    address = EmailAddress.find_or_create_by!(email: email)
    account.subscriptions.create!({ email_address: address, source: :signup }.merge(attributes))
  end
end
