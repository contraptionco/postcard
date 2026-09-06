# frozen_string_literal: true

require 'test_helper'

class OauthConfigTest < ActiveSupport::TestCase
  test 'configured Google provider retains OAuth state validation' do
    original_config = Rails.configuration.google_oauth
    original_provider = Devise.omniauth_configs[:google_oauth2]
    Rails.configuration.google_oauth = { client_id: 'test-client', client_secret: 'test-secret' }

    load Rails.root.join('config/initializers/devise.rb')
    provider = Devise.omniauth_configs.fetch(:google_oauth2)
    strategy = provider.strategy_class.new(nil, *provider.args, **provider.options)
    refute strategy.options.provider_ignores_state
  ensure
    Rails.configuration.google_oauth = original_config
    if original_provider
      Devise.omniauth_configs[:google_oauth2] = original_provider
    else
      Devise.omniauth_configs.delete(:google_oauth2)
    end
  end
end
