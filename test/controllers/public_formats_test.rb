# frozen_string_literal: true

require 'test_helper'

class PublicFormatsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    @account = Account.first
    @other_account = Account.where.not(id: @account.id).first
    @public_post = create_post('A public postcard')
    @older_post = create_post('An older public postcard', published_at: 2.days.ago)
    @unlisted_post = create_post('An unlisted postcard', visibility: :unlisted)
    @hidden_post = create_post('A hidden postcard', visibility: :hidden)
    @draft = create_post('A draft postcard', published_at: nil)
    @archived_post = create_post('An archived postcard', archived: true)
    @other_post = @other_account.posts.create!(subject: 'Another author', body: 'Other content', published_at: 1.day.ago)
  end

  teardown do
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
  end

  test 'reader links work on the solo root host' do
    use_solo_mode
    host! Rails.configuration.base_host
    assert_reader_formats("http://#{Rails.configuration.base_host}")
  end

  test 'reader links work on hosted account subdomains' do
    use_multiuser_mode
    host! @account.postcard_host
    assert_reader_formats("http://#{@account.postcard_host}")
  end

  test 'reader links use a verified custom domain over HTTPS' do
    use_multiuser_mode
    @account.domains.create!(domain: 'reader.example.test', verified: true)
    https!
    host! 'reader.example.test'
    assert_reader_formats('https://reader.example.test')
  end

  test 'reader links preserve a nonstandard local port' do
    use_multiuser_mode
    host! "#{@account.postcard_host}:4321"
    get public_post_path(@public_post)
    assert_response :success
    assert_select "a[href='http://#{@account.postcard_host}:4321/posts.rss']", text: 'RSS feed'
    assert_select "a[href='http://#{@account.postcard_host}:4321/posts/#{@public_post.slug}.md']", text: 'Read as Markdown'
  end

  test 'cached public pages keep reader links on the current request origin' do
    use_multiuser_mode
    cache_store = ActiveSupport::Cache::MemoryStore.new
    controllers = [PublicPagesController, PublicPostsController]
    original_settings = controllers.map { |controller| [controller, controller.perform_caching, controller.cache_store] }
    controllers.each do |controller|
      controller.perform_caching = true
      controller.cache_store = cache_store
    end
    cache_hits = 0
    count_cache_hits = ->(*args) { cache_hits += 1 if args.last[:hit] }

    ActiveSupport::Notifications.subscribed(count_cache_hits, 'cache_read.active_support') do
      [[false, 3000], [false, 4321], [true, 443]].each do |secure, port|
        https! secure
        host! "#{@account.postcard_host}:#{port}"
        origin = "#{secure ? 'https' : 'http'}://#{@account.postcard_host}#{secure ? '' : ":#{port}"}"

        ['/', public_posts_path].each do |path|
          2.times do
            get path
            assert_response :success
            assert_select "a[href='#{origin}/posts.rss']", text: 'RSS feed'
            assert_select "a[href='#{origin}/posts.md']", text: 'Posts as Markdown'
          end
        end
      end
    end
    assert_operator cache_hits, :>, 0
  ensure
    original_settings&.each do |controller, enabled, store|
      controller.perform_caching = enabled
      controller.cache_store = store
    end
  end

  test 'direct unlisted and hidden Markdown stays available without appearing in feeds' do
    use_multiuser_mode
    host! @account.postcard_host

    [@unlisted_post, @hidden_post].each do |post|
      get public_post_path(post)
      assert_response :success
      assert_select "a[href='http://#{@account.postcard_host}/posts/#{post.slug}.md']", text: 'Read as Markdown'
      get public_post_path(post, format: :md)
      assert_response :success
      assert_equal 'text/markdown', response.media_type
      assert_includes response.body, "# #{post.subject}"
    end
  end

  test 'draft archived and other-account posts cannot be downloaded from public routes' do
    use_multiuser_mode
    host! @account.postcard_host

    [@draft, @archived_post, @other_post].each do |post|
      assert_raises(ActiveRecord::RecordNotFound) do
        get public_post_path(post, format: :md)
      end
    end
  end

  test 'the visible feed remains valid when there are no publicly listed posts' do
    use_multiuser_mode
    host! @account.postcard_host
    [@public_post, @older_post].each { |post| post.update!(archived: true) }

    get '/'
    assert_response :success
    assert_select "a[href='http://#{@account.postcard_host}/posts.rss']", text: 'RSS feed'
    get public_posts_path(format: :rss)
    assert_response :success
    assert_empty Nokogiri::XML(response.body).css('item')
    get public_posts_path(format: :md)
    assert_response :success
    [@unlisted_post, @hidden_post, @draft, @archived_post, @other_post].each do |post|
      assert_not_includes response.body, post.subject
    end
  end

  test 'draft previews do not advertise a Markdown URL and their feed links use the public host' do
    # Dashboard routes are conditional at boot, so exercise the configured mode.
    host! Rails.configuration.base_host
    sign_in @account

    get page_post_draft_path(@account, @draft, :review)
    assert_response :success
    assert_select 'a', text: 'Read as Markdown', count: 0
    assert_select "a[href='http://#{@account.host}/posts.rss']", text: 'RSS feed'
  end

  private

  def create_post(subject, **attributes)
    @account.posts.create!({ subject: subject, body: '<p>A readable <strong>postcard</strong>.</p>', published_at: 1.day.ago }.merge(attributes))
  end

  def use_solo_mode
    Rails.configuration.solo_mode = true
    Rails.configuration.multiuser_mode = false
  end

  def use_multiuser_mode
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
  end

  def assert_reader_formats(origin)
    get '/'
    assert_response :success
    assert_select 'nav[aria-label="Reading options"]' do
      assert_select "a[href='#{origin}/posts.rss'][type='application/rss+xml']", text: 'RSS feed'
      assert_select "a[href='#{origin}/posts.md'][type='text/markdown']", text: 'Posts as Markdown'
    end

    get public_posts_path
    assert_response :success
    assert_select "a[href='#{origin}/posts.rss']", text: 'RSS feed'
    assert_select "a[href='#{origin}/posts.md']", text: 'Posts as Markdown'

    get public_posts_path(format: :rss)
    assert_response :success
    assert_equal 'application/rss+xml', response.media_type
    titles = Nokogiri::XML(response.body).css('item title').map(&:text)
    assert_equal [@public_post.subject, @older_post.subject].sort, titles.sort

    get public_posts_path(format: :md)
    assert_response :success
    assert_equal 'text/markdown', response.media_type
    [@public_post, @older_post].each { |post| assert_includes response.body, post.subject }
    [@unlisted_post, @hidden_post, @draft, @archived_post, @other_post].each do |post|
      assert_not_includes response.body, post.subject
    end

    get public_post_path(@public_post)
    assert_response :success
    assert_select "a[href='#{origin}/posts/#{@public_post.slug}.md'][type='text/markdown']", text: 'Read as Markdown'

    get public_post_path(@public_post, format: :md)
    assert_response :success
    assert_equal 'text/markdown', response.media_type
    assert_includes response.body, "# #{@public_post.subject}"
    assert_includes response.body, '**postcard**'
  end
end
