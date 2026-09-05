# frozen_string_literal: true

# Permanently deletes an account and all of its data. Deletion happens in a
# job because the analytics, subscriber, and email tables can hold hundreds of
# thousands of rows for an established account — far too slow for a request.
# The account is locked before this job is enqueued, so the page is already
# offline and sign-in is blocked while deletion runs.
class DestroyAccountJob < ApplicationJob
  queue_as :default

  # If the job retries after the account row is already gone, there is nothing
  # left to do.
  discard_on ActiveJob::DeserializationError

  def perform(account)
    account_id = account.id

    purge_pending_jobs(account)
    purge_analytics(account)

    # Bulk-delete the large tables without per-row callbacks or audits.
    EmailMessage.where(account_id: account_id)
                .or(EmailMessage.where(user: account))
                .or(EmailMessage.where(subscription_id: account.subscriptions.select(:id)))
                .in_batches.delete_all
    account.subscriptions.in_batches.delete_all

    # Pay does not clean up its records when the owner is destroyed. Billing
    # was already canceled at Stripe before this job was enqueued.
    account.pay_customers.each(&:destroy!)

    # Destroys the remainder (posts, domains, imports, feedbacks, attachments)
    # with normal callbacks.
    # The Account association only includes unarchived posts by default.
    Post.unscoped.where(account_id: account_id).find_each(&:destroy!)
    account.destroy!

    purge_audits(account_id)
  end

  private

  def purge_pending_jobs(account)
    SolidQueue::Job.where(finished_at: nil).where.not(active_job_id: job_id).find_each do |queued_job|
      references = global_ids_in(queued_job.arguments)
      next if references.empty? || !references.all? { |reference| account_owns_reference?(account, reference) }

      queued_job.with_lock do
        # A running worker must retain its execution record, including this job.
        queued_job.destroy! unless queued_job.claimed_execution.present? || queued_job.finished?
      end
    rescue ActiveRecord::RecordNotFound
      # A worker may finish/remove a queued job while this sweep runs.
      next
    end
  end

  def global_ids_in(value)
    case value
    when Hash
      return [value['_aj_globalid']] if value.key?('_aj_globalid')

      value.values.flat_map { |nested| global_ids_in(nested) }
    when Array
      value.flat_map { |nested| global_ids_in(nested) }
    else
      []
    end
  end

  def account_owns_reference?(account, reference)
    gid = GlobalID.parse(reference)
    return false unless gid && gid.app == GlobalID.app
    return gid.model_id == account.id.to_s if gid.model_name == 'Account'

    models = { 'Post' => Post, 'Subscription' => Subscription, 'SubscribersImport' => SubscribersImport,
               'Domain' => Domain, 'EmailMessage' => EmailMessage }
    model = models[gid.model_name]
    model && model.unscoped.where(account_id: account.id, id: gid.model_id).exists?
  rescue URI::InvalidURIError, ArgumentError
    false
  end

  def purge_analytics(account)
    # Page views recorded for visitors to the account's page. Uses the GIN
    # jsonb_path_ops index on ahoy_events.properties.
    Ahoy::Event.where('properties @> ?', { account: account.id }.to_json).in_batches.delete_all

    # The account's own tracked events and visits.
    Ahoy::Event.where(user_id: account.id).in_batches.delete_all
    Ahoy::Event.where(visit_id: account.visits.select(:id)).in_batches.delete_all
    account.visits.in_batches.delete_all
  end

  def purge_audits(account_id)
    # Runs last so the audit rows written by the destroys above are removed
    # too — audit snapshots contain account PII.
    Audited::Audit.where(auditable_type: 'Account', auditable_id: account_id)
                  .or(Audited::Audit.where(associated_type: 'Account', associated_id: account_id))
                  .in_batches.delete_all
  end
end
