# frozen_string_literal: true

require 'test_helper'
require 'securerandom'

class SolidCacheTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  CACHE_KEYS = %w[homepage-featured-account first second missing].freeze

  setup do
    @cache_options = {
      namespace: "solid-cache-regression:#{SecureRandom.uuid}",
      # The test job adapter prevents writes from starting background expiry threads.
      expiry_method: :job
    }
    # The application's test cache is a null store; exercise the production adapter explicitly.
    @cache = SolidCache::Store.new(@cache_options)
  end

  teardown do
    @cache&.delete_multi(CACHE_KEYS.dup)
  end

  test 'fetch persists a cache miss and reuses it from another store instance' do
    key = 'homepage-featured-account'
    value = { 'id' => 42, 'username' => 'featured' }

    assert_equal value, @cache.fetch(key, expires_in: 1.hour) { value }

    reader = SolidCache::Store.new(@cache_options)
    assert_equal value, reader.fetch(key, expires_in: 1.hour) { flunk 'cache hit recomputed the value' }
  end

  test 'batch operations persist, overwrite, read, and delete cache entries' do
    values = { 'first' => { 'title' => 'First' }, 'second' => [1, 2] }

    @cache.write_multi(values)
    assert_equal values, @cache.read_multi('first', 'second', 'missing')

    @cache.write_multi('first' => { 'title' => 'Updated' })
    assert_equal({ 'first' => { 'title' => 'Updated' }, 'second' => [1, 2] },
                 @cache.read_multi('first', 'second'))

    @cache.delete_multi(values.keys)
    assert_empty @cache.read_multi('first', 'second')
  end
end
