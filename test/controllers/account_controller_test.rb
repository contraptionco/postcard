# frozen_string_literal: true

require 'test_helper'

class AccountControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
    @account = accounts(:new_user)
    host! Rails.configuration.base_host
  end

  teardown do
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
  end

  def use_multiuser_mode
    Rails.configuration.solo_mode = false
    Rails.configuration.multiuser_mode = true
  end

  def use_solo_mode
    Rails.configuration.solo_mode = true
    Rails.configuration.multiuser_mode = false
  end

  test 'destroy locks the account, signs out, and enqueues deletion with correct confirmation' do
    use_multiuser_mode
    sign_in @account

    assert_enqueued_with(job: DestroyAccountJob, args: [@account]) do
      delete page_account_path(@account), params: { confirmation: @account.postcard_host }
    end

    assert_redirected_to root_path
    assert @account.reload.access_locked?
  end

  test 'enqueued deletion removes the account and its associated data' do
    use_multiuser_mode
    sign_in @account
    @account.posts.create!(subject: 'Hello world', body: 'My first post')

    delete page_account_path(@account), params: { confirmation: @account.postcard_host }

    assert_difference -> { Account.count } => -1, -> { Post.unscoped.count } => -1 do
      perform_enqueued_jobs(only: DestroyAccountJob)
    end

    assert_not Account.exists?(@account.id)
  end

  test 'destroy accepts confirmation regardless of case and surrounding whitespace' do
    use_multiuser_mode
    sign_in @account

    assert_enqueued_with(job: DestroyAccountJob) do
      delete page_account_path(@account), params: { confirmation: " #{@account.postcard_host.upcase} " }
    end

    assert_redirected_to root_path
  end

  test 'destroy does nothing without a matching confirmation' do
    use_multiuser_mode
    sign_in @account

    assert_no_enqueued_jobs(only: DestroyAccountJob) do
      delete page_account_path(@account), params: { confirmation: 'wrong-address' }
    end

    assert_redirected_to page_support_path(@account)
    assert_not @account.reload.access_locked?
  end

  test 'destroy is not available in solo mode' do
    use_solo_mode
    sign_in @account

    assert_no_enqueued_jobs(only: DestroyAccountJob) do
      delete page_account_path(@account), params: { confirmation: @account.postcard_host }
    end

    assert_not @account.reload.access_locked?
  end

  test 'cannot destroy another account' do
    use_multiuser_mode
    other_account = accounts(:grandfathered_user)
    sign_in @account

    assert_no_enqueued_jobs(only: DestroyAccountJob) do
      delete page_account_path(other_account), params: { confirmation: other_account.postcard_host }
    end

    assert_redirected_to page_path(@account)
    assert_not other_account.reload.access_locked?
  end

  test 'destroy requires authentication' do
    use_multiuser_mode

    assert_no_enqueued_jobs(only: DestroyAccountJob) do
      delete page_account_path(@account), params: { confirmation: @account.postcard_host }
    end

    assert_response :redirect
    assert_match %r{/accounts/sign_in}, response.location
  end

  test 'devise registration destroy redirects to settings in multiuser mode' do
    use_multiuser_mode
    sign_in @account

    assert_no_difference 'Account.count' do
      delete account_registration_path
    end

    assert_redirected_to page_support_path(@account)
    assert Account.exists?(@account.id)
  end
end
