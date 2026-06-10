# frozen_string_literal: true

require 'test_helper'

class SupportControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    @account = accounts(:new_user)
    host! Rails.configuration.base_host
  end

  teardown do
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
    Rails.application.reload_routes!
  end

  test 'shows contact details and the delete account section in multiuser mode' do
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
    # The dashboard layout links to routes that are only drawn outside solo
    # mode, so redraw them under the toggled configuration.
    Rails.application.reload_routes!
    sign_in @account

    get page_support_path(@account)

    assert_response :success
    assert_match 'postcard@contraption.co', response.body
    assert_match 'Delete account', response.body
    assert_match @account.postcard_host, response.body
  end

  test 'redirects to the page in solo mode' do
    Rails.configuration.solo_mode = true
    Rails.configuration.multiuser_mode = false
    sign_in @account

    get page_support_path(@account)

    assert_redirected_to page_path(@account)
  end

  test 'requires authentication' do
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true

    get page_support_path(@account)

    assert_response :redirect
    assert_match %r{/accounts/sign_in}, response.location
  end
end
