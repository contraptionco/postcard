# frozen_string_literal: true

require 'test_helper'

class PinnedPostsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
    @account = accounts(:new_user)
    @other_account = accounts(:grandfathered_user)
    host! Rails.configuration.base_host
    sign_in @account
  end

  teardown do
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
  end

  test 'can feature an owned public post and remove the feature' do
    post = create_post(@account)

    put page_account_path(@account), params: { account: { pinned_post_id: post.id } }

    assert_redirected_to page_posts_path(@account)
    assert_equal post.id, @account.reload.pinned_post_id

    put page_account_path(@account), params: { account: { pinned_post_id: '' } }

    assert_redirected_to page_posts_path(@account)
    assert_nil @account.reload.pinned_post_id
  end

  test 'can continue to feature an owned unlisted post' do
    post = create_post(@account, visibility: :unlisted)

    put page_account_path(@account), params: { account: { pinned_post_id: post.id } }

    assert_redirected_to page_posts_path(@account)
    assert_equal post.id, @account.reload.pinned_post_id
  end

  test 'cannot feature another account published post or draft' do
    [Time.current, nil].each do |published_at|
      post = create_post(@other_account, published_at: published_at)

      put page_account_path(@account), params: { account: { pinned_post_id: post.id } }

      assert_response :unprocessable_entity
      assert_nil @account.reload.pinned_post_id
    end
  end

  test 'cannot feature a draft hidden or archived post' do
    [{ published_at: nil }, { visibility: :hidden }, { archived: true }].each do |attributes|
      post = create_post(@account, **attributes)

      put page_account_path(@account), params: { account: { pinned_post_id: post.id } }

      assert_response :unprocessable_entity
      assert_nil @account.reload.pinned_post_id
    end
  end

  test 'invalid pin leaves the existing feature unchanged' do
    existing_post = create_post(@account)
    @account.update!(pinned_post: existing_post)

    put page_account_path(@account), params: { account: { pinned_post_id: -1 } }

    assert_response :unprocessable_entity
    assert_equal existing_post.id, @account.reload.pinned_post_id
  end

  test 'cannot update the feature on another account' do
    post = create_post(@other_account)

    put page_account_path(@other_account), params: { account: { pinned_post_id: post.id } }

    assert_redirected_to page_path(@account)
    assert_nil @other_account.reload.pinned_post_id
  end

  test 'public homepage does not disclose a foreign draft from a historical invalid pin' do
    post = create_post(@other_account, published_at: nil, subject: 'Confidential draft', body: 'Private draft content')
    @account.update_column(:pinned_post_id, post.id)
    sign_out @account
    host! @account.postcard_host

    get root_path

    assert_response :success
    assert_no_match 'Confidential draft', response.body
    assert_no_match 'Private draft content', response.body
  end

  test 'marketing homepage excludes historical invalid featured pins' do
    @account.update!(slug: 'philipithomas')
    post = create_post(@other_account, published_at: nil, subject: 'Confidential draft', body: 'Private draft content')
    @account.update_column(:pinned_post_id, post.id)
    sign_out @account

    get '/'

    assert_response :success
    assert_no_match 'Confidential draft', response.body
    assert_no_match 'Private draft content', response.body
  end

  private

  def create_post(account, **attributes)
    account.posts.create!({ subject: 'A post', body: 'Post content', published_at: Time.current }.merge(attributes))
  end
end
