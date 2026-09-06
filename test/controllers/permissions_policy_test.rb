# frozen_string_literal: true

require 'test_helper'

class PermissionsPolicyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = Rails.configuration.solo_mode ? Account.first : accounts(:grandfathered_user)
    @account.update!(grandfathered: true)
  end

  test 'public homepage restricts unused device APIs with the current response header' do
    host! @account.host
    get root_path
    assert_response :success
    assert_device_policy
    assert_select 'form[action="/"]', minimum: 1
  end

  test 'published video and customer embed retain browser media and payment capabilities' do
    @account.update!(code: <<~HTML)
      <iframe title="Newsletter video" src="https://video.example.test/embed/123"
              allow="autoplay; fullscreen; picture-in-picture; payment" allowfullscreen></iframe>
    HTML
    post = @account.posts.create!(
      subject: 'Video postcard', slug: 'video-postcard', published_at: Time.current,
      body: '<p>A short video.</p><video controls><source src="https://video.example.test/postcard.mp4" type="video/mp4"></video>'
    )
    host! @account.host
    get public_post_path(post)
    assert_response :success
    assert_device_policy
    assert_select 'video[controls] source[src=?]', 'https://video.example.test/postcard.mp4'
    assert_select 'iframe[title="Newsletter video"]' do |frames|
      assert_equal 'autoplay; fullscreen; picture-in-picture; payment', frames.first['allow']
      assert frames.first.key?('allowfullscreen')
    end
  end

  test 'authenticated editor has the same policy while retaining file uploads' do
    sign_in @account
    host! Rails.configuration.base_host
    get edit_page_path(@account)
    assert_response :success
    assert_device_policy
    assert_select 'input[type="file"][name="account[photo]"]', count: 1
    assert_select 'input[type="file"][name="account[cover]"]', count: 1
  end

  private

  def assert_device_policy
    policy = response.headers.fetch('Permissions-Policy').split(', ').to_h { |directive| directive.split('=', 2) }
    %w[accelerometer camera geolocation gyroscope magnetometer microphone midi usb].each do |feature|
      assert_equal '()', policy[feature], "Expected #{feature} to be disabled"
    end
    %w[autoplay fullscreen payment picture-in-picture encrypted-media].each do |feature|
      refute policy.key?(feature), "Expected #{feature} to retain browser defaults and iframe delegation"
    end
    assert_nil response.headers['Feature-Policy'], 'Do not ship a second, potentially contradictory legacy policy'
  end
end
