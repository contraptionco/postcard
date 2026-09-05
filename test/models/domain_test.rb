# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class DomainTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body) do
    def read_body
      body
    end
  end

  setup do
    @domain = Domain.create!(
      account: accounts(:new_user),
      domain: 'example.test',
      verified: false
    )
  end

  test 'reads automatic verification status without manually triggering verification' do
    requests = []
    response = FakeResponse.new('200', '{"verificationStatus":"unverified"}')

    Domain.stub(:render_service_request, lambda { |path, method, _body = nil|
      requests << [path, method]
      response
    }) do
      @domain.update_verification_status
    end

    assert_equal [['/example.test', Net::HTTP::Get]], requests
    assert_not @domain.reload.verified?
  end

  test 'manually triggers verification before reading stale domain status' do
    requests = []
    responses = [
      FakeResponse.new('202', ''),
      FakeResponse.new('200', '{"verificationStatus":"unverified"}')
    ]

    Domain.stub(:render_service_request, lambda { |path, method, _body = nil|
      requests << [path, method]
      responses.shift
    }) do
      @domain.update_verification_status(trigger_verification: true)
    end

    assert_equal [
      ['/example.test/verify', Net::HTTP::Post],
      ['/example.test', Net::HTTP::Get]
    ], requests
  end

  test 'raises a rate limit error without making a follow-up request' do
    requests = []
    response = FakeResponse.new('429', 'rate limited')

    error = assert_raises(Domain::RenderRateLimitError) do
      Domain.stub(:render_service_request, lambda { |path, method, _body = nil|
        requests << [path, method]
        response
      }) do
        @domain.update_verification_status(trigger_verification: true)
      end
    end

    assert_equal [['/example.test/verify', Net::HTTP::Post]], requests
    assert_includes error.message, '429'
  end

  test 'raises a rate limit error when reading automatic verification status' do
    requests = []
    response = FakeResponse.new('429', 'rate limited')

    error = assert_raises(Domain::RenderRateLimitError) do
      Domain.stub(:render_service_request, lambda { |path, method, _body = nil|
        requests << [path, method]
        response
      }) do
        @domain.update_verification_status
      end
    end

    assert_equal [['/example.test', Net::HTTP::Get]], requests
    assert_includes error.message, '429'
  end
end
