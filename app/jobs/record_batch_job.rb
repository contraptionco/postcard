# frozen_string_literal: true

# For jobs whose top-level record arguments represent independent units of work.
# New enqueue sites should prefer one record per job. Older persisted batches
# must still process their live records when another record has been deleted.
class RecordBatchJob < ApplicationJob
  private

  def deserialize_arguments(serialized_arguments)
    serialized_arguments.each_with_object([]) do |argument, records|
      records.concat(super([argument]))
    rescue ActiveJob::DeserializationError => error
      missing_record = argument.is_a?(Hash) && argument.key?('_aj_globalid') &&
                       error.cause.is_a?(ActiveRecord::RecordNotFound)
      raise error unless missing_record
    end
  end
end
