# frozen_string_literal: true

require 'test_helper'

class MarketingPagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @modes = [Rails.configuration.solo_mode, Rails.configuration.multiuser_mode]
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
    Rails.application.reload_routes!
    host! Rails.configuration.base_host
  end

  teardown do
    Rails.configuration.solo_mode, Rails.configuration.multiuser_mode = @modes
    Rails.application.reload_routes!
  end

  test 'a fresh installation explains how Postcard works without a featured account' do
    get '/'
    assert_response :success
    assert_select 'h1', count: 1
    assert_select 'h2', text: 'How it works'
    assert_select 'a[href=?]', new_account_registration_path, minimum: 1
    assert_select '[data-testid=homepage-preview]', count: 0
  end

  test 'featured preview is one named link without nested interactive content' do
    account = accounts(:grandfathered_user)
    account.update!(slug: 'philipithomas', description: 'A personal corner of the internet.')
    get '/'
    assert_response :success
    assert_select '[data-testid=homepage-preview] > a[aria-label][rel=noopener]', count: 1 do
      assert_select 'h2', text: account.name
    end
    assert_select '[data-testid=homepage-preview] a a, [data-testid=homepage-preview] button, [data-testid=homepage-preview] input', count: 0
    assert_select 'h1', count: 1
    assert_select 'ul[role=list] > div', count: 0
  end

  test 'a featured account without a photo or post still renders the homepage' do
    accounts(:grandfathered_user).update!(slug: 'philipithomas')
    get '/'
    assert_response :success
    assert_select 'h2', text: 'How it works'
  end

  test 'the Revue landing page can reuse the responsive preview' do
    accounts(:grandfathered_user).update!(slug: 'philipithomas')
    get '/alternative/revue'
    assert_response :success
    assert_select '#homepage-title', text: "Revue alternative that doesn't shut down"
    assert_select '[data-testid=homepage-preview]', count: 1
  end

  test 'a featured post renders without a profile photo' do
    account = accounts(:grandfathered_user)
    post = account.posts.create!(subject: 'Field notes', body: 'A public update', published_at: Time.current)
    account.update!(slug: 'philipithomas', pinned_post: post)
    get '/'
    assert_response :success
    assert_includes response.body, 'Field notes'
  end

  test 'an invalid historical pin is not included in the marketing page' do
    account = accounts(:grandfathered_user)
    post = accounts(:new_user).posts.create!(subject: 'Private draft', body: 'Never publish this')
    account.update_columns(slug: 'philipithomas', pinned_post_id: post.id)
    get '/'
    assert_response :success
    assert_not_includes response.body, 'Private draft'
    assert_not_includes response.body, 'Never publish this'
  end

  test 'locked accounts are omitted from the featured preview and galleries' do
    account = accounts(:grandfathered_user)
    account.update_columns(slug: 'philipithomas', locked_at: Time.current)
    get '/'
    assert_response :success
    assert_select '[data-testid=homepage-preview]', count: 0
    assert_not_includes response.body, account.name
  end

  test 'signed in accounts go straight to their page' do
    account = accounts(:grandfathered_user)
    sign_in account
    get '/'
    assert_redirected_to page_path(account)
  end

  test 'signed in visitors still see the alternative page preview' do
    account = accounts(:grandfathered_user)
    account.update!(slug: 'philipithomas')
    sign_in account
    get '/alternative/revue'
    assert_response :success
    assert_select '[data-testid=homepage-preview]', count: 1
    assert_select '#homepage-title', text: "Revue alternative that doesn't shut down"
  end

  test 'solo mode renders the personal site' do
    Rails.configuration.solo_mode = true
    Rails.configuration.multiuser_mode = false
    get '/'
    assert_response :success
    assert_select '[data-testid=homepage-preview]', count: 0
    assert_select 'h1', text: Account.first.name
  end
end
