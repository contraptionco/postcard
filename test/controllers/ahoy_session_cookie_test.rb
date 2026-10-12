# frozen_string_literal: true

require 'test_helper'

class AhoySessionCookieTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Ahoy ignores bots, so a diagnostic or Rack::Test user agent would miss the
  # account lookup that loads the session and caused the cookie overwrite.
  BROWSER_USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

  setup do
    host! Rails.configuration.base_host
    https!
    @original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original_forgery_protection
  end

  test 'a late analytics response cannot overwrite the Google authorization state cookie' do
    get new_account_session_path, headers: browser_headers
    assert_response :success
    csrf_token = response.parsed_body.at_css('meta[name="csrf-token"]')['content']
    form_token = response.parsed_body.at_css('form[action="/accounts/auth/google_oauth2"] input[name="authenticity_token"]')['value']
    earlier_cookie = cookies[session_cookie_name]
    assert earlier_cookie.present?

    post account_google_oauth2_omniauth_authorize_path,
         params: { authenticity_token: form_token }, headers: browser_headers
    assert_response :redirect
    state = Rack::Utils.parse_query(URI(response.location).query).fetch('state')
    assert_not_equal earlier_cookie, cookies[session_cookie_name]

    # This request started before authorization, but its response arrives after
    # the authorization response. Separate jars reproduce that ordering without
    # timing-sensitive threads or requests to Google.
    late_request = open_session do |client|
      client.host! Rails.configuration.base_host
      client.https!
      client.cookies[session_cookie_name] = earlier_cookie
    end
    assert_difference -> { Ahoy::Event.where(name: 'late-oauth-click').count }, 1 do
      late_request.post '/ahoy/events', params: analytics_event('late-oauth-click'), as: :json,
                        headers: browser_headers.merge('X-CSRF-Token' => csrf_token)
    end
    assert_equal 200, late_request.response.status
    if session_cookie_written?(late_request.response)
      cookies[session_cookie_name] = late_request.cookies[session_cookie_name]
    end

    get account_google_oauth2_omniauth_callback_path,
        params: { state: state, error: 'access_denied' }, headers: browser_headers
    assert_redirected_to new_account_session_path
    assert_match(/Access denied/i, flash[:alert])
    assert_not session_cookie_written?(late_request.response)
  end

  test 'Google authorization still rejects a callback with the wrong state' do
    get new_account_session_path, headers: browser_headers
    form_token = response.parsed_body.at_css('form[action="/accounts/auth/google_oauth2"] input[name="authenticity_token"]')['value']
    post account_google_oauth2_omniauth_authorize_path,
         params: { authenticity_token: form_token }, headers: browser_headers
    assert_response :redirect

    get account_google_oauth2_omniauth_callback_path,
        params: { state: 'incorrect-state', error: 'access_denied' }, headers: browser_headers

    assert_redirected_to new_account_session_path
    assert_match(/Csrf detected/i, flash[:alert])
  end

  test 'analytics reads the signed in account without writing a session cookie' do
    account = accounts(:grandfathered_user)
    sign_in account
    get page_path(account), headers: browser_headers
    assert_response :success
    csrf_token = response.parsed_body.at_css('meta[name="csrf-token"]')['content']
    established_cookie = cookies[session_cookie_name]
    assert established_cookie.present?

    assert_difference -> { Ahoy::Event.where(name: 'signed-in-analytics').count }, 1 do
      post '/ahoy/events', params: analytics_event('signed-in-analytics'), as: :json,
           headers: browser_headers.merge('X-CSRF-Token' => csrf_token)
    end

    assert_response :success
    assert_equal account.id, Ahoy::Event.find_by!(name: 'signed-in-analytics').user_id
    assert_not session_cookie_written?(response)
    assert_equal established_cookie, cookies[session_cookie_name]

    post '/ahoy/visits', params: { js: true }, as: :json,
         headers: browser_headers.merge('X-CSRF-Token' => csrf_token)
    assert_response :success
    assert_equal account.id, Ahoy::Visit.find_by!(visit_token: response.parsed_body.fetch('visit_token')).user_id
    assert_not session_cookie_written?(response)
    assert_equal established_cookie, cookies[session_cookie_name]

    get page_path(account), headers: browser_headers
    assert_response :success
    assert_equal account.id, request.env['warden'].user(:account).id
  end

  private

  def session_cookie_name
    Rails.application.config.session_options.fetch(:key)
  end

  def session_cookie_written?(reply)
    Array(reply.headers['Set-Cookie']).any? { |cookie| cookie.match?(/(?:\A|\n)#{Regexp.escape(session_cookie_name)}=/) }
  end

  def browser_headers
    { 'User-Agent' => BROWSER_USER_AGENT }
  end

  def analytics_event(name)
    { events: [{ id: SecureRandom.uuid, name: name, properties: {}, time: Time.current.iso8601 }], js: true }
  end
end
