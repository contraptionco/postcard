# frozen_string_literal: true

require 'test_helper'

class GhostIntegrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:grandfathered_user)
    @other = accounts(:new_user)
    @account.update!(admin: true)
    host! Rails.configuration.base_host
  end

  test 'administrator sees the destination and can opt their own page in and out without transferring subscribers' do
    sign_in @account
    get edit_page_path(@account)
    assert_response :success
    assert_select 'form[action=?]', page_ghost_integration_path(@account) do
      assert_select 'input[name="account[sync_to_ghost]"][type="checkbox"]', count: 1
    end
    assert_includes response.body, 'fixed Contraption Ghost destination'

    assert_no_enqueued_jobs only: SubscribeToContraptionGhostJob do
      %w[1 0].each do |setting|
        patch page_ghost_integration_path(@account), params: { account: { sync_to_ghost: setting, admin: false } }
        assert_redirected_to edit_page_path(@account)
        assert_equal setting == '1', @account.reload.sync_to_ghost?
        assert @account.admin?
      end
    end
  end

  test 'ordinary authors cannot see or enable the integration through either update route' do
    @account.update!(admin: false)
    sign_in @account
    get edit_page_path(@account)
    assert_response :success
    assert_select 'form[action=?]', page_ghost_integration_path(@account), count: 0

    patch page_ghost_integration_path(@account), params: { account: { sync_to_ghost: '1' } }
    assert_response :forbidden
    put page_path(@account), params: { account: { name: @account.name, sync_to_ghost: '1' } }
    assert_response :redirect
    refute @account.reload.sync_to_ghost?
  end

  test 'administrators cannot enable the fixed destination for another author' do
    sign_in @account
    get edit_page_path(@other)
    assert_response :success
    assert_select 'form[action=?]', page_ghost_integration_path(@other), count: 0
    patch page_ghost_integration_path(@other), params: { account: { sync_to_ghost: '1' } }
    assert_response :forbidden
    refute @other.reload.sync_to_ghost?
  end

  test 'guests cannot change the setting' do
    patch page_ghost_integration_path(@account), params: { account: { sync_to_ghost: '1' } }
    assert_response :redirect
    assert_equal new_account_session_path, URI(response.location).path
    refute @account.reload.sync_to_ghost?
  end
end
