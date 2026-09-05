# frozen_string_literal: true

# Retired integration. Keep this class so already queued jobs can drain after
# deployment without contacting Ghost or failing to deserialize the job class.
# Remove it once no persisted jobs reference SubscribeToContraptionGhostJob.
class SubscribeToContraptionGhostJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(*_legacy_arguments); end
end
