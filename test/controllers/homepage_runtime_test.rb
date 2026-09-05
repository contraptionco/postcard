# frozen_string_literal: true

require 'test_helper'

class HomepageRuntimeTest < ActionDispatch::IntegrationTest
  test 'an existing solo account renders a working subscription form' do
    original_solo_mode = Rails.configuration.solo_mode
    original_multiuser_mode = Rails.configuration.multiuser_mode
    Rails.configuration.solo_mode = true
    Rails.configuration.multiuser_mode = false
    host! Rails.configuration.base_host

    get '/'

    assert_response :success
    assert_select 'input[name="email_address[email]"]'
  ensure
    Rails.configuration.solo_mode = original_solo_mode
    Rails.configuration.multiuser_mode = original_multiuser_mode
  end
end
