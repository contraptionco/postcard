# frozen_string_literal: true

require 'test_helper'

class PinnedPostTest < ActiveSupport::TestCase
  test 'model validation rejects a foreign draft regardless of controller' do
    account = accounts(:new_user)
    post = accounts(:grandfathered_user).posts.create!(subject: 'Private draft', body: 'Private content')

    refute account.update(pinned_post: post)
    assert account.errors.added?(:pinned_post, 'must be one of your published, visible posts')
  end

  test 'public pin excludes historical hidden and unpublished pins' do
    account = accounts(:new_user)
    [{ visibility: :hidden, published_at: Time.current }, { published_at: nil }].each do |attributes|
      post = account.posts.create!({ subject: 'A post', body: 'Post content' }.merge(attributes))
      account.update_column(:pinned_post_id, post.id)

      assert_nil account.reload.public_pinned_post
    end
  end

  test 'public pin returns an owned published post' do
    account = accounts(:new_user)
    post = account.posts.create!(subject: 'A post', body: 'Post content', published_at: Time.current)
    account.update!(pinned_post: post)

    assert_equal post, account.reload.public_pinned_post
  end

  test 'unpublishing a post removes its homepage feature' do
    account = accounts(:new_user)
    post = account.posts.create!(subject: 'A post', body: 'Post content', published_at: Time.current)
    account.update!(pinned_post: post)

    post.update!(published_at: nil)

    assert_nil account.reload.pinned_post_id
  end
end
