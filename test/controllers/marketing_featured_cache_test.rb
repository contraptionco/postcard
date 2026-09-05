# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class MarketingFeaturedCacheTest < ActionDispatch::IntegrationTest
  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    @original_cache = Rails.cache
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @account = accounts(:grandfathered_user)
    @account.update!(slug: 'philipithomas')
    File.open(Rails.root.join('app/assets/images/logo/icon.png')) do |photo|
      @account.photo.attach(io: photo, filename: 'profile.png', content_type: 'image/png')
    end
    @post = @account.posts.create!(
      subject: 'Cached feature original title', body: 'Cached feature original body',
      published_at: Time.current
    )
    @account.update!(pinned_post: @post)
    host! Rails.configuration.base_host
  end

  teardown do
    @account.photo.purge
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
    Rails.cache = @original_cache
  end

  {
    'hidden' => { visibility: :hidden },
    'unpublished' => { published_at: nil },
    'archived' => { archived: true }
  }.each do |state, attributes|
    test "warm marketing cache stops exposing a post immediately after it becomes #{state}" do
      with_production_cache do
        get '/'
        assert_featured_in_both_previews(@post)

        # Exercise real persistence and pin-removal callbacks after warming the
        # cache. Neither the test nor production code clears the cache.
        @post.update!(attributes)

        get '/'
        assert_feature_absent(@post)
      end
    end
  end

  test 'warm marketing cache immediately reflects removal of the featured pin' do
    with_production_cache do
      get '/'
      assert_featured_in_both_previews(@post)

      @account.update!(pinned_post: nil)

      get '/'
      # The public "Read newest post" link can remain after unpinning; the
      # hero card and social preview must stop featuring the post.
      assert_feature_absent(@post, check_url: false)
    end
  end

  test 'warm marketing cache shows a replacement pin instead of the previous post' do
    with_production_cache do
      get '/'
      assert_featured_in_both_previews(@post)

      replacement = @account.posts.create!(
        subject: 'Replacement feature title', body: 'Replacement feature body', published_at: Time.current
      )
      @account.update!(pinned_post: replacement)

      get '/'
      assert_feature_absent(@post)
      assert_featured_in_both_previews(replacement)
    end
  end

  test 'a legacy cached account cannot disclose a post hidden after the entry was written' do
    with_production_cache do
      Rails.cache.write('homepage-featured-account', Account.includes(:pinned_post).find(@account.id))
      @post.update!(visibility: :hidden)

      get '/'
      assert_feature_absent(@post)
    end
  end

  test 'warm marketing cache stops featuring an account after it is locked' do
    with_production_cache do
      get '/'
      assert_featured_in_both_previews(@post)
      @account.update!(locked_at: Time.current)

      get '/'
      assert_feature_absent(@post)
      assert_not_includes response.body, @account.name
    end
  end

  private

  def with_production_cache(&block)
    # Keep the test environment and its offline mail/job adapters. Only select
    # the production cache path after the app has already booted normally.
    Rails.env.stub(:production?, true, &block)
  end

  def assert_featured_in_both_previews(post)
    assert_response :success
    assert_select 'p.text-xl', text: post.subject, count: 1 # Hero's public-page card
    assert_select 'p', text: "I just published \"#{post.subject}\" on my website - check it out:", count: 1
    assert_includes response.body, post.body.to_plain_text
  end

  def assert_feature_absent(post, check_url: true)
    assert_response :success
    assert_not_includes response.body, post.subject
    assert_not_includes response.body, post.body.to_plain_text
    assert_not_includes response.body, post.slug if check_url
  end
end
