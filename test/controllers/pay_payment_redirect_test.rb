# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class PayPaymentRedirectTest < ActionDispatch::IntegrationTest
  Payment = Struct.new(:client_secret, :status, :customer) do
    def succeeded?
      true
    end
  end

  setup do
    host! Rails.configuration.base_host
    @payment = Payment.new('test-secret', 'succeeded', 'test-customer')
  end

  [
    'javascript:alert(document.domain)',
    'data:text/html,<script>alert(1)</script>',
    'https://example.com/phishing',
    '//example.com/phishing',
    '/\\example.com/phishing',
    "/\n/example.com/phishing",
    '%invalid',
    nil
  ].each do |unsafe_back|
    test "payment page rejects unsafe return path #{unsafe_back.inspect}" do
      Pay::Payment.stub(:from_id, @payment) do
        get '/pay/payments/pi_test', params: { back: unsafe_back }
      end

      assert_response :success
      assert_select 'a', text: I18n.t('pay.back'), count: 1 do |links|
        assert_equal '/', links.first['href']
      end
    end
  end

  test 'payment page preserves a local return path and query' do
    Pay::Payment.stub(:from_id, @payment) do
      get '/pay/payments/pi_test', params: { back: '/pages/test-user?tab=billing' }
    end

    assert_response :success
    assert_select 'a[href="/pages/test-user?tab=billing"]', text: I18n.t('pay.back')
  end

  test 'only Stripe webhook routes are exposed' do
    assert_equal [:stripe], Pay.enabled_processors
    stripe_route = Pay::Engine.routes.recognize_path('/webhooks/stripe', method: :post)
    assert_equal 'pay/webhooks/stripe', stripe_route[:controller]

    %w[paddle paddle_billing braintree].each do |processor|
      assert_raises(ActionController::RoutingError) do
        post "/pay/webhooks/#{processor}"
      end
    end
  end
end
