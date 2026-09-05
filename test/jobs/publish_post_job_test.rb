# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class PublishPostJobTest < ActiveSupport::TestCase
  setup do
    @post = accounts(:new_user).posts.create!(subject: 'Hello', body: 'Post body', published_at: Time.current)
    2.times do |index|
      @post.account.subscriptions.create!(source: :import, verified_at: Time.current,
        email_address: EmailAddress.create!(email: "delivery-#{index}@example.com"))
    end
  end

  test 'ordinary recipient failure does not prevent delivery to the next recipient' do
    deliveries = []
    AccountMailer.stub(:new_post, lambda { |_post, subscription|
      deliveries << subscription.id
      raise IOError, 'delivery failed' if deliveries.length == 1

      Object.new.tap { |mail| def mail.deliver_now; end }
    }) do
      PublishPostJob.perform_now(@post)
    end

    assert_equal 2, deliveries.length
    assert @post.reload.finished_sending?
  end

  test 'shutdown interrupts are propagated without marking delivery finished' do
    AccountMailer.stub(:new_post, ->(*) { raise Interrupt, 'shutdown' }) do
      assert_raises(Interrupt) { PublishPostJob.perform_now(@post) }
    end
    refute @post.reload.finished_sending?
  end
end
