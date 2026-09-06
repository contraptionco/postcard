# frozen_string_literal: true

require 'test_helper'

class AccountRegistrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:new_user)
    host! Rails.configuration.base_host
  end

  test 'account settings update the password after confirming the current password' do
    sign_in @account
    put account_registration_path, params: {
      account: { current_password: 'password123', password: 'new-password-123', password_confirmation: 'new-password-123' }
    }

    assert_response :redirect
    assert @account.reload.valid_password?('new-password-123')
    refute @account.valid_password?('password123')
  end

  test 'account settings reject the wrong current password without changing account details' do
    sign_in @account
    put account_registration_path, params: {
      account: { email: 'changed@example.com', current_password: 'incorrect' }
    }

    assert_response :unprocessable_entity
    assert_equal 'newuser@example.com', @account.reload.email
    assert_select 'a[href=?]', new_account_password_path, text: 'Reset your password'
  end

  test 'account settings require authentication' do
    put account_registration_path, params: { account: { password: 'new-password-123', current_password: 'password123' } }

    assert_response :redirect
    assert_match %r{/accounts/sign_in}, response.location
    assert @account.reload.valid_password?('password123')
  end
end
