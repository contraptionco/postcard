# frozen_string_literal: true

require 'test_helper'

class SetupControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @modes = [Rails.configuration.solo_mode, Rails.configuration.multiuser_mode]
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
    Rails.application.reload_routes!
    @account = accounts(:grandfathered_user)
    host! Rails.configuration.base_host
    sign_in @account
  end

  teardown do
    Rails.configuration.solo_mode, Rails.configuration.multiuser_mode = @modes
    Rails.application.reload_routes!
  end

  test 'invalid hosted subdomain stays on the form with validation errors' do
    old_slug = @account.slug
    put page_setup_path(@account, :domain_hosted), params: { account: { slug: 'invalid domain!' } }
    assert_response :unprocessable_entity
    assert_select 'input[name="account[slug]"]' do |inputs|
      assert_equal 'invalid domain!', inputs.first['value']
    end
    assert_includes response.body, 'can only contain'
    assert_equal old_slug, @account.reload.slug
  end

  test 'valid hosted subdomain advances to the sharing step' do
    put page_setup_path(@account, :domain_hosted), params: { account: { slug: 'my-new-home' } }
    assert_equal 'my-new-home', @account.reload.slug
    assert_redirected_to page_setup_path(@account, :denouement)
  end

  test 'hosted subdomain cannot update another account' do
    other = accounts(:new_user)
    put page_setup_path(other, :domain_hosted), params: { account: { slug: 'stolen-home' } }
    assert_redirected_to page_path(@account)
    assert_not_equal 'stolen-home', other.reload.slug
  end

  test 'solo mode skips domain onboarding without changing the account' do
    Rails.configuration.solo_mode = true
    Rails.configuration.multiuser_mode = false
    put page_setup_path(@account, :domain_hosted), params: { account: { slug: 'another-home' } }
    assert_redirected_to page_path(@account)
    assert_not_equal 'another-home', @account.reload.slug
  end

  test 'the page editor gives the theme color input its visible label' do
    get edit_page_path(@account)
    assert_response :success
    assert_select 'label[for=account_accent_color]', text: 'Theme color'
    assert_select 'input#account_accent_color[name="account[accent_color]"][type=color]', count: 1
  end
end
