# frozen_string_literal: true

require 'test_helper'
require 'yaml'

class SolidQueueConfigTest < ActiveSupport::TestCase
  test 'uses low-frequency polling while preserving two-job concurrency' do
    config = YAML.load_file(Rails.root.join('config/solid_queue.yml'), aliases: true).fetch('default')
    dispatcher = config.fetch('dispatchers').sole
    worker = config.fetch('workers').sole
    recurring_tasks = dispatcher.fetch('recurring_tasks')

    assert_equal 60, dispatcher.fetch('polling_interval')
    assert_equal false, dispatcher.fetch('concurrency_maintenance')
    assert_equal 30, worker.fetch('polling_interval')
    assert_equal 1, worker.fetch('processes')
    assert_equal 2, worker.fetch('threads')

    assert_equal 'every 15 minutes', recurring_tasks.dig('verify_recent_domains', 'schedule')
    assert_equal ['recent'], recurring_tasks.dig('verify_recent_domains', 'args')
    assert_equal '0 4 * * * America/New_York', recurring_tasks.dig('verify_stale_domains', 'schedule')
    assert_equal ['stale'], recurring_tasks.dig('verify_stale_domains', 'args')
  end
end
