# frozen_string_literal: true

require 'test_helper'

class PublicPostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
    @account = accounts(:new_user)
    host! @account.postcard_host
  end

  teardown do
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
  end

  test 'hidden posts remain accessible by direct link with indexing disabled in HTML and Markdown' do
    post = create_post(visibility: :hidden)

    [nil, :md].each do |format|
      get public_post_path(post, format: format)

      assert_response :success
      assert_equal 'noindex, nofollow', response.headers['X-Robots-Tag']
      assert_match 'Post content', response.body
    end
  end

  test 'public and unlisted posts remain indexable in HTML and Markdown' do
    %i[public unlisted].each do |visibility|
      post = create_post(visibility: visibility)

      [nil, :md].each do |format|
        get public_post_path(post, format: format)

        assert_response :success
        assert_nil response.headers['X-Robots-Tag']
      end
    end
  end

  test 'drafts cannot be read as HTML or Markdown' do
    post = create_post(published_at: nil)

    [nil, :md].each do |format|
      assert_raises ActiveRecord::RecordNotFound do
        get public_post_path(post, format: format)
      end
    end
  end

  private

  def create_post(**attributes)
    @account.posts.create!({ subject: 'A post', body: 'Post content', published_at: Time.current }.merge(attributes))
  end
end
