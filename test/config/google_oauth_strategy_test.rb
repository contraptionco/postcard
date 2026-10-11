# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class GoogleOauthStrategyTest < ActiveSupport::TestCase
  test 'Google Workspace authorization code callback validates ID token claims and returns the account identity' do
    status, env = callback

    assert_equal 200, status
    auth = env.fetch('omniauth.auth')
    assert_equal 'google_oauth2', auth.provider
    assert_equal 'google-user-123', auth.uid
    assert_equal 'member@example.com', auth.info.email
    assert_equal true, auth.info.email_verified
    assert_equal 'example.com', auth.extra.id_info.hd
    assert_equal 'test-client', auth.extra.id_info.aud
  end

  test 'Google callback rejects an ID token issued for another client' do
    assert_invalid_claims({ 'aud' => 'another-client' }, JWT::InvalidAudError)
  end

  test 'Google callback rejects an ID token from another issuer' do
    assert_invalid_claims({ 'iss' => 'https://example.com' }, JWT::InvalidIssuerError)
  end

  test 'Google callback rejects an expired ID token' do
    assert_invalid_claims({ 'exp' => Time.now.to_i - 120 }, JWT::ExpiredSignature)
  end

  test 'Google callback rejects an ID token that is not valid yet' do
    assert_invalid_claims({ 'nbf' => Time.now.to_i + 120 }, JWT::ImmatureSignature)
  end

  test 'Google callback requires the ID token identity and expiration claims' do
    %w[iss aud exp sub].each do |claim|
      status, env = callback(claims: valid_claims.except(claim))

      assert_equal 401, status, "missing #{claim} must fail authentication"
      assert_kind_of JWT::MissingRequiredClaim, env['omniauth.error']
      assert_nil env['omniauth.auth']
    end
  end

  test 'Google callback does not expose an unverified email as the account email' do
    status, env = callback(email_verified: false)

    assert_equal 200, status
    assert_nil env.fetch('omniauth.auth').info.email
    assert_equal false, env.fetch('omniauth.auth').info.email_verified
  end

  test 'Google callback without an ID token uses verified userinfo with an opaque access token' do
    status, env = callback(include_id_token: false)

    assert_equal 200, status
    auth = env.fetch('omniauth.auth')
    assert_equal 'google-user-123', auth.uid
    assert_equal 'member@example.com', auth.info.email
    assert_nil auth.extra.id_info
  end

  test 'Google callback rejects mismatched OAuth state before exchanging the code' do
    status, env = callback(state: 'unexpected-state')

    assert_equal 401, status
    assert_equal :csrf_detected, env['omniauth.error.type']
    assert_nil env['omniauth.auth']
    assert_not_requested :post, 'https://oauth2.googleapis.com/token'
  end

  private

  def valid_claims
    {
      'iss' => 'https://accounts.google.com',
      'aud' => 'test-client',
      'sub' => 'google-user-123',
      'exp' => Time.now.to_i + 3600,
      'hd' => 'example.com'
    }
  end

  def assert_invalid_claims(overrides, error_class)
    status, env = callback(claims: valid_claims.merge(overrides))

    assert_equal 401, status
    assert_kind_of error_class, env['omniauth.error']
    assert_nil env['omniauth.auth']
  end

  def callback(claims: valid_claims, include_id_token: true, email_verified: true, state: 'expected-state')
    token_response = { access_token: 'opaque-access-token', token_type: 'Bearer', expires_in: 3600 }
    # These tokens arrive from the stubbed server-to-server code exchange, never
    # from caller-supplied ID-token authentication (which requires Google keys).
    token_response[:id_token] = JWT.encode(claims, 'test-only-signing-key', 'HS256') if include_id_token
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .with(body: hash_including('code' => 'test-authorization-code', 'grant_type' => 'authorization_code'))
      .to_return(json_response(token_response))
    stub_request(:get, 'https://www.googleapis.com/oauth2/v3/userinfo')
      .with(headers: { 'Authorization' => 'Bearer opaque-access-token' })
      .to_return(json_response(sub: 'google-user-123', email: 'member@example.com',
                               email_verified: email_verified, name: 'Test Member', hd: 'example.com'))
    stub_request(:post, 'https://www.googleapis.com/oauth2/v3/tokeninfo')
      .with(body: { access_token: 'opaque-access-token' })
      .to_return(json_response(aud: 'test-client', scope: 'openid email profile'))

    strategy = OmniAuth::Strategies::GoogleOauth2.new(
      ->(_env) { [200, {}, ['authenticated']] }, 'test-client', 'test-secret', path_prefix: '/accounts/auth'
    )
    env = Rack::MockRequest.env_for(
      "https://postcard.example/accounts/auth/google_oauth2/callback?code=test-authorization-code&state=#{state}",
      'rack.session' => { 'omniauth.state' => 'expected-state' }
    )
    failure_app = ->(_env) { [401, {}, ['authentication failed']] }
    status, = OmniAuth.config.stub(:on_failure, -> { failure_app }) do
      strategy.call(env)
    end
    [status, env]
  end

  def json_response(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end
end
