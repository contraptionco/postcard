# frozen_string_literal: true

require 'test_helper'

class PostPublishingFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @account = Rails.configuration.solo_mode ? Account.first : accounts(:grandfathered_user)
    @account.update!(grandfathered: true)
    @other_account = Account.where.not(id: @account.id).first
    host! Rails.configuration.base_host
    sign_in @account
  end

  test 'an author can create a blank draft and open its editor' do
    assert_difference -> { @account.posts.count }, 1 do
      assert_no_enqueued_jobs(only: PublishPostJob) do
        post page_posts_path(@account)
      end
    end

    draft = @account.posts.first
    assert draft.draft?
    assert_nil draft.subject
    assert draft.body.blank?
    assert draft.slug.present?
    assert_redirected_to page_post_draft_index_path(@account, draft)
    follow_redirect!
    assert_redirected_to page_post_draft_path(@account, draft, :write)
    follow_redirect!
    assert_response :success
    assert_select "form#post-#{draft.id}"
  end

  test 'saving an incomplete draft preserves work without publishing or emailing' do
    draft = create_draft

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_draft_path(@account, draft, :write),
          params: { post: { subject: 'A title for later', body: '' }, commit: 'save' }
    end

    assert_redirected_to page_posts_path(@account)
    assert_equal 'Draft saved', flash[:notice]
    assert_equal 'A title for later', draft.reload.subject
    assert draft.body.blank?
    assert draft.draft?
  end

  test 'review validates incomplete work and keeps it in the editor' do
    draft = create_draft

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_draft_path(@account, draft, :write),
          params: { post: { subject: 'Not finished', body: '' }, commit: 'review' }
    end

    assert_response :bad_request
    assert_select "form#post-#{draft.id}"
    assert_match "Body can&#39;t be empty", response.body
    assert_equal 'Not finished', draft.reload.subject
    assert draft.draft?
  end

  test 'autosave accepts unfinished work and returns the Turbo response without publishing' do
    draft = create_draft

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_draft_path(@account, draft, :write),
          params: { post: { subject: '', body: '<p>A sentence before its title.</p>' } },
          headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
    end

    assert_response :success
    assert_equal 'text/vnd.turbo-stream.html', response.media_type
    assert_equal '', draft.reload.subject
    assert_equal 'A sentence before its title.', draft.body.to_plain_text
    assert draft.draft?
  end

  test 'reviewing and publishing valid work saves content and schedules exactly one newsletter' do
    draft = create_draft

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_draft_path(@account, draft, :write),
          params: { post: { subject: 'A letter from home', body: '<p>Our first update.</p>' }, commit: 'review' }
    end

    assert_redirected_to page_post_draft_path(@account, draft, :review)
    draft.reload
    follow_redirect!
    assert_redirected_to page_post_draft_path(@account, draft, :review)
    follow_redirect!
    assert_response :success
    assert_select 'a[data-turbo-method="put"]', text: 'Publish →'
    assert draft.draft?

    travel_to Time.zone.local(2026, 9, 5, 12, 0, 0) do
      assert_enqueued_with(job: PublishPostJob, args: [draft]) do
        assert_enqueued_with(job: PingSearchEnginesJob, args: [@account], at: 1.hour.from_now) do
          put page_post_draft_path(@account, draft, :review)
        end
      end
      assert_equal Time.current, draft.reload.published_at
    end

    assert_response :see_other
    assert_redirected_to page_posts_path(@account, share_post: draft.slug)
    assert_equal 'A letter from home', draft.subject
    assert_equal 'Our first update.', draft.body.to_plain_text
    assert_equal draft, @account.reload.pinned_post
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == PublishPostJob }

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_draft_path(@account, draft, :review)
    end
    assert_redirected_to edit_page_post_path(@account, draft)
  end

  test 'a direct publish request for an invalid draft returns to editing with validation errors' do
    draft = create_draft

    assert_no_enqueued_jobs(only: [PublishPostJob, PingSearchEnginesJob]) do
      put page_post_draft_path(@account, draft, :review)
    end

    assert_response :see_other
    assert_redirected_to page_post_draft_path(@account, draft, :write)
    assert_includes flash[:alert], "Subject can't be blank"
    assert_includes flash[:alert], "Body can't be empty"
    assert draft.reload.draft?
    assert_nil @account.reload.pinned_post_id
    follow_redirect!
    assert_response :success
    assert_select "form#post-#{draft.id}[action='#{page_post_draft_path(@account, draft, :write)}']"
  end

  test 'published posts leave every draft step through a stable editor URL' do
    published = create_published

    %i[write review confirmation].each do |step|
      get page_post_draft_path(@account, published, step)
      assert_redirected_to edit_page_post_path(@account, published)
      follow_redirect!
      assert_response :success
      assert_select "form#post-#{published.id}"
    end
  end

  test 'an author can edit a published post without sending another newsletter' do
    published = create_published
    published_at = published.reload.published_at

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_path(@account, published),
          params: { post: { subject: 'A corrected title', body: '<p>A clearer update.</p>', visibility: 'unlisted' } }
    end

    assert_redirected_to page_posts_path(@account)
    assert_equal 'Post updated', flash[:notice]
    assert_equal 'A corrected title', published.reload.subject
    assert_equal 'A clearer update.', published.body.to_plain_text
    assert published.visibility_unlisted?
    assert_equal published_at, published.published_at
  end

  test 'invalid published edits show errors and preserve the last published version' do
    published = create_published
    original_subject = published.subject
    original_body = published.body.to_plain_text
    original_slug = published.slug

    assert_no_enqueued_jobs(only: PublishPostJob) do
      put page_post_path(@account, published), params: { post: { subject: '', body: '' } }
    end

    assert_response :unprocessable_entity
    assert_match "Subject can&#39;t be blank", response.body
    assert_equal original_subject, published.reload.subject
    assert_equal original_body, published.body.to_plain_text
    assert_equal original_slug, published.slug
    assert published.published?
  end

  test 'deleting a draft removes it while deleting a published post archives it' do
    draft = create_draft
    published = create_published

    assert_difference -> { Post.unscoped.count }, -1 do
      delete page_post_path(@account, draft)
    end
    assert_response :see_other
    assert_not Post.unscoped.exists?(draft.id)

    assert_no_difference -> { Post.unscoped.count } do
      delete page_post_path(@account, published)
    end
    assert_response :see_other
    assert Post.unscoped.find(published.id).archived?
    assert_not @account.posts.exists?(published.id)
  end

  test 'guests cannot read the editor or mutate posts through any authoring route' do
    draft = create_draft
    published = create_published
    sign_out @account

    assert_authoring_unchanged(draft, published) do
      authoring_requests(@account, draft, published).each do |method, path, params|
        public_send(method, path, params: params)
        assert_response :redirect
        assert_equal new_account_session_path, URI(response.location).path
      end
    end
  end

  test 'another account cannot read the editor or mutate posts through any authoring route' do
    draft = create_draft
    published = create_published
    @other_account.update!(grandfathered: true)
    sign_out @account
    sign_in @other_account

    assert_authoring_unchanged(draft, published) do
      authoring_requests(@account, draft, published).each do |method, path, params|
        public_send(method, path, params: params)
        assert_redirected_to page_path(@other_account)
      end
    end
  end

  test 'foreign post slugs cannot be used under the signed-in authors own path' do
    foreign_draft = @other_account.posts.create!(subject: 'Someone elses draft', body: 'Private work')
    foreign_published = @other_account.posts.create!(subject: 'Someone elses post', body: 'Public work', published_at: 1.day.ago)

    assert_authoring_unchanged(foreign_draft, foreign_published) do
      authoring_requests(@account, foreign_draft, foreign_published).reject { |method, _path, _params| method == :post }.each do |method, path, params|
        sign_in @account
        assert_raises(ActiveRecord::RecordNotFound, "#{method} #{path}") do
          public_send(method, path, params: params)
        end
      end
    end
  end

  private

  def create_draft
    @account.posts.build.tap { |draft| draft.save!(validate: false) }
  end

  def create_published
    @account.posts.create!(subject: 'A published letter', body: '<p>The original text.</p>', published_at: 1.day.ago)
  end

  def authoring_requests(account, draft, published)
    [
      [:get, edit_page_post_path(account, published), {}],
      [:get, page_post_draft_path(account, draft, :write), {}],
      [:get, page_post_draft_path(account, draft, :review), {}],
      [:get, page_post_draft_path(account, draft, :confirmation), {}],
      [:post, page_posts_path(account), {}],
      [:put, page_post_draft_path(account, draft, :write), { post: { subject: 'Tampered', body: 'Tampered' }, commit: 'save' }],
      [:put, page_post_draft_path(account, draft, :review), {}],
      [:put, page_post_path(account, published), { post: { subject: 'Tampered', body: 'Tampered' } }],
      [:delete, page_post_path(account, draft), {}],
      [:delete, page_post_path(account, published), {}]
    ]
  end

  def assert_authoring_unchanged(*posts)
    snapshots = posts.map { |post| [post.reload.attributes, post.body.to_plain_text] }
    assert_no_difference -> { Post.unscoped.count } do
      assert_no_enqueued_jobs(only: [PublishPostJob, PingSearchEnginesJob]) { yield }
    end
    posts.zip(snapshots).each do |post, (attributes, body)|
      assert_equal attributes, post.reload.attributes
      assert_equal body, post.body.to_plain_text
    end
  end
end
