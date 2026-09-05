# frozen_string_literal: true

class PublishPostJob < ApplicationJob
  queue_as :critical

  def perform(*posts) # rubocop:disable Metrics/MethodLength
    posts.each do |post|
      next if post.account.access_locked?

      raise 'not published' unless post.published?

      PostInAdminChatJob.perform_later "[New post - #{post.account.email}] #{post.subject} #{post.url}"

      post.account.subscriptions.active.find_each do |subscription|
        AccountMailer.new_post(post, subscription).deliver_now
      rescue StandardError => e
        Rails.logger.error "Error sending post to #{subscription.email_address.email}: #{e}"
        # For AWS SES bounces and complaints, we may want to add specific error handling later
      end

      post.update(finished_sending: true)
    end
  end
end
