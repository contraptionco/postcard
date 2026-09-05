# frozen_string_literal: true

require 'test_helper'

class DraftValidationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @account = Rails.configuration.solo_mode ? Account.first : accounts(:grandfathered_user)
    @account.update!(grandfathered: true)
    host! Rails.configuration.base_host
    sign_in @account
    @draft = @account.posts.create!(subject: 'Original title', body: '<p>Original body.</p>')
  end

  test 'an empty draft can be saved without scheduling publication' do
    assert_no_enqueued_jobs(only: [PublishPostJob, PingSearchEnginesJob]) do
      put write_path, params: { post: { subject: '', body: '' }, commit: 'save' }
    end

    assert_redirected_to page_posts_path(@account)
    assert_equal '', @draft.reload.subject
    assert @draft.body.blank?
    assert @draft.draft?
  end

  test 'HTML saves accept a 255-character title' do
    put write_path, params: { post: { subject: 'a' * 255, body: '<p>Saved body.</p>' }, commit: 'save' }

    assert_redirected_to page_posts_path(@account)
    assert_equal 'a' * 255, @draft.reload.subject
    assert_equal 'Saved body.', @draft.body.to_plain_text
  end

  test 'HTML saves reject a 256-character title and preserve submitted content in the editor' do
    put write_path, params: { post: { subject: 'a' * 256, body: '<p>Unsaved body.</p>' }, commit: 'save' }

    assert_invalid_save_preserves_input
  end

  test 'review rejects an oversized title before advancing to publication' do
    assert_no_enqueued_jobs(only: [PublishPostJob, PingSearchEnginesJob]) do
      put write_path, params: { post: { subject: 'a' * 256, body: '<p>Unsaved body.</p>' }, commit: 'review' }
    end

    assert_invalid_save_preserves_input
  end

  test 'Turbo autosave accepts a 255-character title with an unfinished body' do
    put write_path, params: { post: { subject: 'a' * 255, body: '' } }, headers: turbo_headers

    assert_response :success
    assert_equal 'text/vnd.turbo-stream.html', response.media_type
    assert_equal 'a' * 255, @draft.reload.subject
    assert @draft.body.blank?
    assert @draft.draft?
  end

  test 'Turbo autosave returns a recoverable HTML validation response for an oversized title' do
    put write_path, params: { post: { subject: 'a' * 256, body: '<p>Unsaved body.</p>' } }, headers: turbo_headers

    assert_invalid_save_preserves_input
  end

  test 'autosaves keep the existing draft URL without reserving intermediate title aliases' do
    original_slug = @draft.slug

    assert_no_difference('FriendlyId::Slug.count') do
      ['A', 'A new', 'A new letter'].each do |subject|
        put write_path, params: { post: { subject: subject, body: '<p>Work in progress.</p>' } }, headers: turbo_headers

        assert_response :success
        assert_equal original_slug, @draft.reload.slug
      end
    end

    assert_difference('FriendlyId::Slug.count', 1) do
      put write_path, params: { post: { subject: 'A final letter', body: '<p>Ready to send.</p>' }, commit: 'review' }
    end

    @draft.reload
    assert_response :redirect
    follow_redirect!
    follow_redirect! if response.redirect?
    assert_response :success
    assert_equal page_post_draft_path(@account, @draft, :review), path
    assert_equal 'a-final-letter', @draft.slug
    assert_equal @draft, @account.posts.friendly.find(original_slug)
  end

  test 'a duplicate 255-character title can be saved and reviewed with a unique slug' do
    title = 'a' * 255
    existing = @account.posts.create!(subject: title, body: '<p>Another post.</p>')

    put write_path, params: { post: { subject: title, body: '<p>New post.</p>' }, commit: 'save' }
    assert_redirected_to page_posts_path(@account)
    assert_equal title, @draft.reload.subject

    put write_path, params: { post: { subject: title, body: '<p>New post.</p>' }, commit: 'review' }
    @draft.reload
    assert_response :redirect
    follow_redirect!
    follow_redirect! if response.redirect?
    assert_response :success
    assert_equal page_post_draft_path(@account, @draft, :review), path
    assert_not_equal existing.slug, @draft.slug
    assert_equal @draft, @account.posts.friendly.find(@draft.slug)
  end

  test 'direct publication refuses a blank subject or body without changing persisted publication state' do
    [{ subject: '', body: '<p>Some body.</p>' }, { subject: 'Some title', body: '' }].each do |attributes|
      @draft.assign_attributes(attributes)
      @draft.save!(context: :draft)

      assert_no_enqueued_jobs(only: [PublishPostJob, PingSearchEnginesJob]) do
        put page_post_draft_path(@account, @draft, :review)
      end

      assert_response :see_other
      assert_redirected_to write_path
      assert flash[:alert].present?
      assert @draft.reload.draft?
      assert_nil @account.reload.pinned_post
      follow_redirect!
      assert_response :success
      assert_select "form#post-#{@draft.id}[action='#{write_path}']"
    end
  end

  private

  def write_path
    page_post_draft_path(@account, @draft, :write)
  end

  def turbo_headers
    { 'Accept' => 'text/vnd.turbo-stream.html' }
  end

  def assert_invalid_save_preserves_input
    assert_response :unprocessable_entity
    assert_equal 'text/html', response.media_type
    assert_select "form#post-#{@draft.id}[action='#{write_path}']"
    assert_select 'input[name="post[subject]"]' do |fields|
      assert_equal 'a' * 256, fields.first['value']
    end
    assert_select 'h1[data-editable-target="content"]', text: 'a' * 256
    assert_match 'Unsaved body.', response.body
    assert_match 'Subject is too long', response.body
    assert_equal 'Original title', @draft.reload.subject
    assert_equal 'Original body.', @draft.body.to_plain_text
    assert @draft.draft?
  end
end
