# frozen_string_literal: true

class VerifyDomainsJob < ApplicationJob
  RECENT = 'recent'
  STALE = 'stale'
  RECENT_WINDOW = 1.week
  BATCH_SIZE = 25

  def perform(cadence = RECENT)
    # Only run in multi-user mode where custom domains are supported
    return unless Rails.configuration.multiuser_mode

    cadence = cadence.to_s
    domains_for(cadence).each do |domain|
      break unless verify_domain(domain, trigger_verification: cadence == STALE)
    end
  end

  private

  def verify_domain(domain, trigger_verification:)
    domain.update_verification_status(trigger_verification: trigger_verification)
    true
  rescue Domain::RenderRateLimitError => e
    Rails.logger.warn "Render rate limit reached while verifying #{domain.domain} (#{domain.id}): #{e.message}"
    false
  rescue StandardError => e
    Rails.logger.error "Error verifying domain #{domain.domain} (#{domain.id}): #{e.class}: #{e.message}"
    true
  end

  def domains_for(cadence)
    unverified_domains(cadence)
      .order(Arel.sql('RANDOM()'))
      .limit(BATCH_SIZE)
  end

  def unverified_domains(cadence)
    domains = Domain.where(verified: false)
    cutoff = RECENT_WINDOW.ago

    case cadence
    when RECENT
      domains.where('created_at >= ?', cutoff)
    when STALE
      domains.where('created_at < ?', cutoff)
    else
      raise ArgumentError, "Unknown verification cadence: #{cadence}"
    end
  end
end
