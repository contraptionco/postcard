# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class DomainNetworkTest < ActiveSupport::TestCase
  class FakeHttp
    attr_accessor :use_ssl, :open_timeout, :read_timeout, :write_timeout
    attr_reader :requests

    def initialize
      @requests = []
    end

    def request(request)
      @requests << request
      DomainTestResponse.new('200', '{}')
    end
  end
  DomainTestResponse = Struct.new(:code, :body) do
    def read_body = body
  end

  test 'Render requests preserve JSON escaping and request structure' do
    previous_solo_mode = Rails.configuration.solo_mode
    Rails.configuration.solo_mode = false
    requests = []
    response = DomainTestResponse.new('201', '[]')
    host = 'example.photography'

    Domain.stub(:render_service_request, ->(path, method, body) { requests << [path, method, JSON.parse(body)]; response }) do
      Domain.register(accounts(:new_user), host)
    end

    assert_equal [['', Net::HTTP::Post, { 'name' => host }]], requests
  ensure
    Rails.configuration.solo_mode = previous_solo_mode
  end

  test 'Render and liveness HTTP requests have bounded connection read and write times' do
    clients = []
    Net::HTTP.stub(:new, ->(*) { FakeHttp.new.tap { |http| clients << http } }) do
      Domain.render_service_request('/example.test', Net::HTTP::Get)
      Domain.new(domain: 'example.test').send(:liveness_check)
    end

    assert_equal 2, clients.length
    clients.each do |http|
      assert http.use_ssl
      assert_equal 5, http.open_timeout
      assert_equal 10, http.read_timeout
      assert_equal 10, http.write_timeout
    end
    assert_equal '/.postcard', clients.last.requests.first.path
  end

  test 'only development test domains and their subdomains are localhost domains' do
    %w[lvh.me test.lvh.me fuf.me test.fuf.me].each { |host| assert Domain.localhost_domain?(host) }
    %w[fbi.com test.fbi.com example.com fakelvh.me].each { |host| refute Domain.localhost_domain?(host) }
  end

  test 'invalid custom domains are rejected before registration side effects' do
    previous_solo_mode = Rails.configuration.solo_mode
    Rails.configuration.solo_mode = false
    requests = []
    Domain.stub(:render_service_request, ->(*) { requests << true }) do
      ['example.test","extra":"value', 'http://example.test', '-bad.example', 'bad-.example',
       'a' * 64 + '.example', '127.0.0.1', nil].each do |host|
        assert_raises(ActiveRecord::RecordInvalid) { Domain.register(accounts(:new_user), host) }
      end
    end
    assert_empty requests
  ensure
    Rails.configuration.solo_mode = previous_solo_mode
  end

  test 'custom domains support long and internationalized suffixes with normalized labels' do
    %w[example.design example.studio example.photography example.xn--p1ai].each do |host|
      domain = Domain.new(account: accounts(:new_user), domain: " #{host.upcase} ")
      assert domain.valid?, domain.errors.full_messages.join(', ')
      assert_equal host, domain.domain
    end
  end

end
