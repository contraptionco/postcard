class PostInAdminChatJob < ApplicationJob
  queue_as :default

  def perform(message)
    Rails.logger.info("Posting in admin chat: #{message}")

    admin_chat_url = Rails.configuration.admin_chat_url

    unless admin_chat_url
      Rails.logger.error "ADMIN_CHAT_URL is not configured. Skipping admin chat post: #{message}"
      return
    end

    # Prefix dev messages to make them easy to spot.
    message = "[DEV] #{message}" if Rails.env.development?

    uri = URI.parse(admin_chat_url)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "text/plain; charset=utf-8")
    request.body = message

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10, write_timeout: 10) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Failed to post in admin chat (HTTP #{response.code}): #{response.message}"
    end
  rescue StandardError => e
    Rails.logger.error "Exception while posting in admin chat: #{e.message}"
  end
end
