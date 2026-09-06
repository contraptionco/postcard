# frozen_string_literal: true

class EnrichAccountJob < RecordBatchJob
  queue_as :critical

  def perform(*accounts)
    accounts.each do |account|
      account.enrich
      account.save!
    end
  end
end
