# frozen_string_literal: true

class CleanupTrackingDataJob < ApplicationJob
  queue_as :low

  RETENTION_PERIOD = 2.weeks
  DEFAULT_BATCH_SIZE = 1_000

  TARGETS = [
    { name: 'Ahoy::Event', columns: %i[time], batch: true },
    {
      name: 'Ahoy::Visit',
      columns: %i[started_at],
      batch: true,
      dependents: [
        { name: 'Ahoy::Event', foreign_key: :visit_id }
      ]
    },
    { name: 'Ahoy::Click', columns: %i[updated_at created_at] },
    { name: 'SolidCache::Entry', columns: %i[updated_at created_at], batch: true }
  ].freeze

  def perform(retention_period: RETENTION_PERIOD)
    cutoff = retention_period.ago
    results = TARGETS.index_with { |target| cleanup_target(target, cutoff) }

    # Only finished queue history is disposable. Let Solid Queue manage worker
    # and semaphore lifecycles; old pending/failed/claimed work must survive.
    SolidQueue::Job.clear_finished_in_batches(batch_size: DEFAULT_BATCH_SIZE, finished_before: cutoff)

    # EmailMessage contains functional unsubscribe tokens, not just tracking
    # data. Its records are removed when the owning account/post is deleted.
    log_results(results, cutoff)
  end

  private

  def cleanup_target(target, cutoff)
    klass = constantize(target[:name])
    unless klass
      Rails.logger.warn("[CleanupTrackingDataJob] Unable to find #{target[:name]}, skipping cleanup")
      return 0
    end

    predicate = cutoff_predicate(klass, target.fetch(:columns))
    unless predicate
      Rails.logger.warn("[CleanupTrackingDataJob] No timestamp columns configured for #{klass.name}, skipping cleanup")
      return 0
    end

    scope = klass.where(predicate, cutoff: cutoff)
    delete_scope(scope, target.fetch(:batch, false), target[:dependents])
  end

  def constantize(value)
    value.is_a?(String) ? value.safe_constantize : value
  end

  def delete_scope(scope, batch, dependents = nil)
    with_statement_timeout_disabled(scope.connection) do
      return delete_relation(scope, dependents) unless batch

      total = 0
      scope.in_batches(of: DEFAULT_BATCH_SIZE) do |relation|
        total += delete_relation(relation, dependents)
      end
      total
    end
  end

  def cutoff_predicate(klass, columns)
    connection = klass.connection
    available_columns = columns.map(&:to_s) & klass.column_names
    return if available_columns.empty?

    table = klass.quoted_table_name
    fallback = connection.quote(Time.at(0).utc)

    expressions = available_columns.map do |column|
      quoted_column = connection.quote_column_name(column)
      "COALESCE(#{table}.#{quoted_column}, #{fallback})"
    end

    if expressions.length == 1
      "#{expressions.first} < :cutoff"
    else
      "GREATEST(#{expressions.join(', ')}) < :cutoff"
    end
  end

  def log_results(results, cutoff)
    results.each do |name, count|
      next unless count.positive?

      Rails.logger.info("[CleanupTrackingDataJob] Removed #{count} #{name} records older than #{cutoff}")
    end
  end

  def delete_relation(relation, dependents)
    ids = Array(relation.pluck(:id)) if dependents

    Array(dependents).each do |dependent|
      dependent_class = constantize(dependent[:name])
      next unless dependent_class

      fk = dependent.fetch(:foreign_key, :id)
      dependent_class.where(fk => ids).delete_all
    end

    ids ? relation.where(id: ids).delete_all : relation.delete_all
  end

  def with_statement_timeout_disabled(connection, &block)
    connection.transaction do
      connection.execute("SET LOCAL statement_timeout = 0")
      block.call
    end
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::QueryCanceled)

    Rails.logger.error("[CleanupTrackingDataJob] Statement timeout could not be disabled: #{e.message}")
    raise
  end
end
