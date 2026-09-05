# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class WebhookTimeoutsTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :message)

  test 'admin chat and Ghost requests use bounded HTTP budgets and preserve payloads' do
    previous_url = Rails.configuration.admin_chat_url
    Rails.configuration.admin_chat_url = 'https://example.test/admin-chat'
    requests = []
    options_seen = []
    http = Object.new
    http.define_singleton_method(:request) { |request| requests << request; Response.new('200', 'OK') }
    start = lambda do |*_args, **options, &block|
      options_seen << options
      block.call(http)
    end

    Net::HTTP.stub(:start, start) do
      PostInAdminChatJob.perform_now('Test announcement')
      Rails.env.stub(:test?, false) do
        SubscribeToContraptionGhostJob.perform_now('subscriber@example.com', 'Subscriber')
      end
    end

    assert_equal 2, requests.length
    assert_equal 'Test announcement', requests.first.body
    assert_equal 'subscriber@example.com', JSON.parse(requests.last.body)['email']
    options_seen.each do |options|
      assert_equal({ use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 10 }, options)
    end
  ensure
    Rails.configuration.admin_chat_url = previous_url
  end

  test 'signup Ghost jobs read account details and do not send for a locked account' do
    account = accounts(:new_user)
    requests = []
    http = Object.new
    http.define_singleton_method(:request) { |request| requests << request; Response.new('200', 'OK') }
    start = ->(*_args, **_options, &block) { block.call(http) }

    Rails.env.stub(:test?, false) do
      Net::HTTP.stub(:start, start) do
        SubscribeToContraptionGhostJob.perform_now(account)
        account.update!(locked_at: Time.current)
        SubscribeToContraptionGhostJob.perform_now(account)
      end
    end

    assert_equal 1, requests.length
    assert_equal({ 'email' => account.email, 'name' => account.name, 'source' => 'postcard' }, JSON.parse(requests.first.body))
  end
end
