class SubscribeToContraptionGhostJob < ApplicationJob
  queue_as :default

  def perform(email, name = nil)
    return if Rails.env.test?

    uri = URI.parse("https://junk-drawer-api.contraption.co/newsletter/subscribe")
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')

    body = {
      "email" => email,
      "source" => "postcard"
    }
    body["name"] = name if name.present?

    request.body = body.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end

    unless response.code == '200'
      raise "Newsletter subscription failed with response code #{response.code} and message #{response.message}"
    end
  end
end
