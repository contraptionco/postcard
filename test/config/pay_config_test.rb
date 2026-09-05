# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class PayConfigTest < ActiveSupport::TestCase
  test 'missing Stripe keys return nil when Rails has no secrets API' do
    with_payment_config do
      assert_nil Pay::Stripe.private_key
      assert_nil Pay::Stripe.public_key
      assert_nil Pay::Stripe.signing_secret
    end
  end

  test 'Stripe keys prefer environment variables over credentials' do
    credentials = { test: { stripe: { private_key: 'scoped-key' } }, stripe: { private_key: 'unscoped-key' } }

    with_payment_config(environment: { 'STRIPE_PRIVATE_KEY' => 'environment-key' }, credentials: credentials) do
      assert_equal 'environment-key', Pay::Stripe.private_key
    end
  end

  test 'Stripe keys read environment scoped credentials' do
    credentials = { test: { stripe: { private_key: 'scoped-key' } }, stripe: { private_key: 'unscoped-key' } }

    with_payment_config(credentials: credentials) do
      assert_equal 'scoped-key', Pay::Stripe.private_key
    end
  end

  test 'Stripe keys read unscoped credentials without the secrets API' do
    with_payment_config(credentials: { stripe: { private_key: 'unscoped-key' } }) do
      assert_equal 'unscoped-key', Pay::Stripe.private_key
    end
  end

  private

  def with_payment_config(environment: {}, credentials: {})
    application = Struct.new(:credentials).new(credentials)

    Rails.stub(:application, application) do
      ENV.stub(:[], ->(key) { environment[key] }) do
        yield
      end
    end
  end
end
