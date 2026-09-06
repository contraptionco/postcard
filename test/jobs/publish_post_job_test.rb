# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class PublishPostJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
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

  test 'queued newsletter does not send after the author account is locked' do
    @post.account.update!(locked_at: Time.current)
    AccountMailer.stub(:new_post, ->(*) { flunk 'Locked accounts must not send newsletters' }) do
      assert_no_enqueued_jobs { PublishPostJob.perform_now(@post.reload) }
    end
    refute @post.reload.finished_sending?
  end

  test 'a persisted batch skips a deleted post and still delivers the other newsletter' do
    deleted_post = accounts(:grandfathered_user).posts.create!(
      subject: 'Deleted newsletter', body: 'Removed content', published_at: Time.current
    )
    payload = JSON.parse(PublishPostJob.new(deleted_post, @post).serialize.to_json)
    deleted_post.destroy!

    assert_emails 2 do
      ActiveJob::Base.execute(payload)
    end
    assert_equal ['delivery-0@example.com', 'delivery-1@example.com'], ActionMailer::Base.deliveries.last(2).flat_map(&:to).sort
    assert @post.reload.finished_sending?
  end

end
