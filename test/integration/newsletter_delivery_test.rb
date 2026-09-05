# frozen_string_literal: true

require 'test_helper'

class NewsletterDeliveryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:grandfathered_user)
    @other_account = accounts(:new_user)
    @post = @account.posts.create!(subject: 'A note from the garden', body: '<p>The tomatoes are ready.</p>',
                                  published_at: Time.current)
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test 'newsletter delivers only to this author’s active subscribers and records each delivery' do
    active = subscribe(@account, 'active@example.com', verified_at: 2.days.ago)
    shared = subscribe(@account, 'shared@example.com', verified_at: 1.day.ago)
    subscribe(@other_account, 'shared@example.com', verified_at: 1.day.ago)
    subscribe(@other_account, 'foreign@example.com', verified_at: 1.day.ago)
    subscribe(@account, 'unverified@example.com')
    subscribe(@account, 'unsubscribed@example.com', verified_at: 2.days.ago, unsubscribed_at: 1.day.ago)

    assert_difference('EmailMessage.count', 2) do
      PublishPostJob.perform_now(@post)
    end

    assert_equal %w[active@example.com shared@example.com], ActionMailer::Base.deliveries.flat_map(&:to).sort
    assert @post.reload.finished_sending?
    messages = EmailMessage.where(post_id: @post.id)
    assert_equal [active.id, shared.id].sort, messages.pluck(:subscription_id).sort
    assert_equal [@account.id], messages.distinct.pluck(:account_id)
    assert_equal [active.email_address_id, shared.email_address_id].sort, messages.pluck(:user_id).sort
    assert_equal ['EmailAddress'], messages.distinct.pluck(:user_type)
    assert messages.all? { |message| message.sent_at.present? }
    assert_equal 2, messages.pluck(:unsubscribe_token).uniq.size
  end

  test 'a serialized mail delivery renders the article, sender, and matching unsubscribe history' do
    subscription = subscribe(@account, 'reader@example.com', verified_at: 1.day.ago)

    assert_difference('EmailMessage.count', 1) do
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
        AccountMailer.new_post(@post, subscription).deliver_later
      end
    end

    mail = ActionMailer::Base.deliveries.fetch(0)
    history = EmailMessage.find_by!(subscription_id: subscription.id, post_id: @post.id)
    expected_sender = if Rails.configuration.solo_mode
                        Rails.configuration.default_email_from
                      else
                        "#{@account.slug}@#{Rails.configuration.default_email_from.split('@').last}"
                      end
    assert_equal [expected_sender], mail.from
    expected_name = Rails.configuration.solo_mode ? Rails.configuration.default_email_from_name : @account.name
    assert_equal expected_name, mail[:from].display_names.first
    assert_equal [@account.email], mail.reply_to
    assert_equal ['reader@example.com'], mail.to
    assert_nil mail.cc
    assert_nil mail.bcc
    assert_equal @post.subject, mail.subject
    assert_equal @post.subject, history.subject
    assert_equal 'AccountMailer#new_post', history.mailer
    assert_equal 'broadcast', mail['message_stream'].value
    html = (mail.html_part || mail).body.decoded
    assert_includes html, 'The tomatoes are ready.'

    links = Nokogiri::HTML(html).css('a').to_h { |link| [link.text.strip, link['href']] }
    article_url = delivered_destination(links.fetch(@post.subject))
    unsubscribe_url = delivered_destination(links.fetch('Unsubscribe'))
    assert_equal @account.host, article_url.host
    assert_equal "/posts/#{@post.slug}", article_url.path
    assert_equal @account.host, unsubscribe_url.host
    assert_equal "/unsubscribe/#{history.unsubscribe_token}", unsubscribe_url.path
  end

  test 'a delivered unsubscribe link removes only the intended membership for a shared address' do
    subscription = subscribe(@account, 'shared-reader@example.com', verified_at: 1.day.ago)
    other_subscription = subscribe(@other_account, 'shared-reader@example.com', verified_at: 1.day.ago)
    AccountMailer.new_post(@post, subscription).deliver_now
    history = EmailMessage.find_by!(subscription_id: subscription.id, post_id: @post.id)
    host! @account.host

    get unsubscription_path(history.unsubscribe_token)
    assert_response :success
    assert subscription.reload.active?

    delete unsubscription_path(history.unsubscribe_token)
    assert_response :see_other
    assert subscription.reload.unsubscribed_at.present?
    assert other_subscription.reload.active?
    assert history.reload.triggered_unsubscribe?
    assert EmailAddress.exists?(subscription.email_address_id)
  end

  test 'newsletter article and unsubscribe links use the author’s verified custom domain' do
    @account.domains.create!(domain: 'letters.example.com', verified: true)
    subscription = subscribe(@account, 'custom-domain-reader@example.com', verified_at: 1.day.ago)
    mail = AccountMailer.new_post(@post, subscription).deliver_now
    history = EmailMessage.find_by!(subscription_id: subscription.id, post_id: @post.id)
    links = Nokogiri::HTML((mail.html_part || mail).body.decoded).css('a')
    article_url = delivered_destination(links.find { |link| link.text.strip == @post.subject }['href'])
    unsubscribe_url = delivered_destination(links.find { |link| link.text.strip == 'Unsubscribe' }['href'])

    assert_equal 'letters.example.com', article_url.host
    assert_equal "/posts/#{@post.slug}", article_url.path
    assert_equal 'letters.example.com', unsubscribe_url.host
    assert_equal "/unsubscribe/#{history.unsubscribe_token}", unsubscribe_url.path
  end

  test 'drafts cannot enqueue a newsletter or search engine ping' do
    @post.update!(published_at: nil)

    assert_no_enqueued_jobs do
      error = assert_raises(RuntimeError) { @post.send_newsletter }
      assert_equal 'Cannot send newsletter unless published', error.message
    end
    assert_not @post.reload.finished_sending?
    assert_empty ActionMailer::Base.deliveries
  end

  test 'already sent posts cannot enqueue another newsletter' do
    @post.update!(finished_sending: true)

    assert_no_enqueued_jobs do
      error = assert_raises(RuntimeError) { @post.send_newsletter }
      assert_equal 'already sent', error.message
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test 'publishing enqueues one delivery and a delayed search engine ping without sending inline' do
    freeze_time do
      assert_enqueued_jobs 2 do
        @post.send_newsletter
      end
      assert_enqueued_with(job: PublishPostJob, args: [@post])
      assert_enqueued_with(job: PingSearchEnginesJob, args: [@account], at: 1.hour.from_now)
      assert_not @post.reload.finished_sending?
      assert_empty ActionMailer::Base.deliveries
    end
  end

  test 'a subscriber who unsubscribes while delivery is queued does not receive the newsletter' do
    subscription = subscribe(@account, 'queued-reader@example.com', verified_at: 1.day.ago)
    @post.send_newsletter
    subscription.unsubscribe!

    assert_no_difference('EmailMessage.count') do
      perform_enqueued_jobs(only: PublishPostJob)
    end

    assert_empty ActionMailer::Base.deliveries
    assert @post.reload.finished_sending?
    assert subscription.reload.unsubscribed_at.present?
  end

  private

  def delivered_destination(href)
    url = URI(href)
    return url unless url.path == '/ahoy/click'

    # Follow the signed tracking endpoint without making an external request to the destination.
    get href
    assert_response :redirect
    URI(response.location)
  end

  def subscribe(account, email, **attributes)
    address = EmailAddress.find_or_create_by!(email: email)
    account.subscriptions.create!({ email_address: address, source: :signup }.merge(attributes))
  end
end
