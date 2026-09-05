# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class VerifyDomainsJobTest < ActiveSupport::TestCase
  setup do
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    Rails.configuration.multiuser_mode = true
  end

  teardown do
    Rails.configuration.multiuser_mode = @original_multiuser_mode
  end

  test 'continues checking domains after one verification fails' do
    attempts = []
    errors = []
    failing_domain = fake_domain(1, 'failing.test') do
      attempts << 'failing.test'
      raise Net::ReadTimeout
    end
    healthy_domain = fake_domain(2, 'healthy.test') { attempts << 'healthy.test' }
    job = VerifyDomainsJob.new

    job.stub(:domains_for, [failing_domain, healthy_domain]) do
      Rails.logger.stub(:error, ->(message) { errors << message }) do
        job.perform
      end
    end

    assert_equal ['failing.test', 'healthy.test'], attempts
    assert_includes errors.first, 'failing.test'
    assert_includes errors.first, 'Net::ReadTimeout'
  end

  test 'stops checking stale domains when Render rate limits verification' do
    attempts = []
    warnings = []
    limited_domain = fake_domain(1, 'limited.test') do
      attempts << 'limited.test'
      raise Domain::RenderRateLimitError, 'rate limited'
    end
    skipped_domain = fake_domain(2, 'skipped.test') { attempts << 'skipped.test' }
    job = VerifyDomainsJob.new

    job.stub(:domains_for, [limited_domain, skipped_domain]) do
      Rails.logger.stub(:warn, ->(message) { warnings << message }) do
        job.perform(VerifyDomainsJob::STALE)
      end
    end

    assert_equal ['limited.test'], attempts
    assert_includes warnings.first, 'limited.test'
  end

  test 'selects recent and stale unverified domains separately' do
    recent = create_domain('recent.test', created_at: 1.hour.ago)
    stale = create_domain('stale.test', created_at: 1.year.ago)
    create_domain('verified.test', created_at: 1.hour.ago, verified: true)
    job = VerifyDomainsJob.new

    assert_equal [recent.id], job.send(:domains_for, VerifyDomainsJob::RECENT).pluck(:id)
    assert_equal [stale.id], job.send(:domains_for, VerifyDomainsJob::STALE).pluck(:id)
  end

  test 'does not query domains outside multi-user mode' do
    Rails.configuration.multiuser_mode = false

    Domain.stub(:where, ->(*) { flunk 'domains should not be queried' }) do
      VerifyDomainsJob.perform_now
    end
  end

  private

  def create_domain(name, created_at:, verified: false)
    Domain.create!(
      account: accounts(:new_user),
      domain: name,
      verified: verified,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def fake_domain(id, name, &verification)
    Struct.new(:id, :domain) do
      define_method(:update_verification_status) do |trigger_verification: false|
        verification.call(trigger_verification)
      end
    end.new(id, name)
  end
end
