# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Missing records cannot be restored by retrying. Other lookup failures,
  # including a database outage, must remain failed/retryable.
  discard_on ActiveJob::DeserializationError do |_job, error|
    raise error unless error.cause.is_a?(ActiveRecord::RecordNotFound)
  end
end
