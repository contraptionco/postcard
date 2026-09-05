# frozen_string_literal: true

require 'test_helper'

class PublicDiscoveryTest < ActionDispatch::IntegrationTest
  setup do
    @account = Rails.configuration.solo_mode ? Account.first : accounts(:grandfathered_user)
    @account.domains.create!(domain: 'letters.example.test', verified: true, apex: true)
    host! 'letters.example.test'
    https!
  end

  test 'sitemap has one canonical location per URL and includes only indexable published posts' do
    public_post = create_post('Public letter')
    other_public_post = create_post('Another public letter')
    unlisted_post = create_post('Unlisted letter', visibility: :unlisted)
    hidden_post = create_post('Hidden letter', visibility: :hidden)
    draft = create_post('Unpublished letter', published_at: nil)
    archived = create_post('Archived letter', archived: true)
    foreign = Account.where.not(id: @account.id).first.posts.create!(subject: 'Foreign letter', body: 'Foreign text', published_at: 1.day.ago)

    get public_page_sitemap_path

    assert_response :success
    xml = Nokogiri::XML(response.body) { |config| config.strict }
    namespace = { 's' => 'http://www.sitemaps.org/schemas/sitemap/0.9' }
    entries = xml.xpath('/s:urlset/s:url', namespace)
    assert_equal 5, entries.length
    entries.each { |entry| assert_equal 1, entry.xpath('s:loc', namespace).length }
    locations = entries.flat_map { |entry| entry.xpath('s:loc', namespace).map(&:text) }
    assert_equal locations.uniq, locations
    assert_includes locations, root_url(host: @account.host, protocol: 'https')
    assert_includes locations, public_posts_url(host: @account.host, protocol: 'https')
    [public_post, other_public_post, unlisted_post].each do |post|
      assert_includes locations, public_post_url(post, host: @account.host, protocol: 'https')
    end
    [hidden_post, draft, archived, foreign].each do |post|
      assert_not locations.any? { |location| URI(location).path == public_post_path(post) }
    end
  end

  test 'llms discovery lists public posts without leaking unlisted hidden draft archived or foreign content' do
    public_post = create_post('A discoverable letter')
    private_posts = [
      create_post('Unlisted discovery sentinel', visibility: :unlisted),
      create_post('Hidden discovery sentinel', visibility: :hidden),
      create_post('Draft discovery sentinel', published_at: nil),
      create_post('Archived discovery sentinel', archived: true),
      Account.where.not(id: @account.id).first.posts.create!(subject: 'Foreign discovery sentinel', body: 'Foreign text', published_at: 1.day.ago)
    ]

    get llms_txt_path

    assert_response :success
    assert_equal 'text/plain', response.media_type
    assert_includes response.body, "# #{@account.name}"
    assert_includes response.body, "[#{public_post.subject}](#{public_post.url}.md)"
    private_posts.each do |post|
      assert_not_includes response.body, post.subject
      assert_not_includes response.body, post.slug
    end
  end

  test 'an archive with only unlisted and hidden posts redirects to the homepage' do
    create_post('Unlisted archive letter', visibility: :unlisted)
    create_post('Hidden archive letter', visibility: :hidden)

    get public_posts_path

    assert_redirected_to @account.url
  end

  test 'sitemap omits the empty archive while retaining direct indexable unlisted posts' do
    unlisted = create_post('Unlisted sitemap letter', visibility: :unlisted)
    create_post('Hidden sitemap letter', visibility: :hidden)

    get public_page_sitemap_path

    assert_response :success
    xml = Nokogiri::XML(response.body) { |config| config.strict }
    locations = xml.xpath('//s:loc', 's' => 'http://www.sitemaps.org/schemas/sitemap/0.9').map(&:text)
    assert_equal [root_url(host: @account.host, protocol: 'https'),
                  public_post_url(unlisted, host: @account.host, protocol: 'https')], locations
  end

  test 'an archive containing public posts renders without including other visibility states' do
    first = create_post('The first public letter', published_at: 2.days.ago)
    latest = create_post('The latest public letter')
    hidden = create_post('Hidden archive sentinel', visibility: :hidden)
    unlisted = create_post('Unlisted archive sentinel', visibility: :unlisted)

    get public_posts_path

    assert_response :success
    [first, latest].each { |post| assert_select "a[href$='#{public_post_path(post)}']", minimum: 1 }
    [hidden, unlisted].each { |post| assert_select "a[href$='#{public_post_path(post)}']", count: 0 }
    assert_select 'h2 a', text: latest.subject
  end

  private

  def create_post(subject, **attributes)
    @account.posts.create!({ subject: subject, body: "<p>#{subject} body</p>", published_at: 1.day.ago }.merge(attributes))
  end
end
