# frozen_string_literal: true

class Domain < ApplicationRecord
  class RenderRateLimitError < StandardError; end

  before_save :downcase_domain
  before_destroy :destroy_in_render
  belongs_to :account, touch: true

  audited

  after_update_commit :post_verification_tasks, :if => :saved_change_to_verified?

  VALID_DOMAIN_REGEX = /\A[a-z0-9]+([\-.]{1}[a-z0-9]+)*\.[a-z]{2,5}\z/
  validates :domain, presence: true,
                     format: { with: VALID_DOMAIN_REGEX },
                     uniqueness: true

  def self.register(account, host) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    raise 'Custom domains disabled in SOLO mode' if Rails.configuration.solo_mode
    raise 'domains already set' if account.domains.length.positive?

    if Rails.env.development? && Domain.localhost_domain?(host)
      return Domain.register_development_domains(account, host)
    end

    response = Domain.render_service_request('', Net::HTTP::Post, "{\"name\":\"#{host}\"}")

    unless response.code == '201'
      raise "Error creating domain #{host} in Render - code #{response.code} \"#{response.body}\""
    end

    JSON.parse(response.read_body).each do |value|
      Domain.create!(
        account: account,
        domain: value['name'],
        verified: value['verificationStatus'] == 'verified',
        apex: value['domainType'] == 'apex',
        redirect_for_name: value['redirectForName'].presence
      )
    end
  end

  LOCALHOST_DOMAINS = ['lvh.me', 'fuf.me', 'fbi.com'].freeze
  def self.localhost_domain?(domain)
    LOCALHOST_DOMAINS.each do |haystack|
      return true if (domain == haystack) || domain.ends_with?(".#{haystack}")
    end
    false
  end

  def self.register_development_domains(account, host) # rubocop:disable Metrics/MethodLength
    domain = Domain.create!(
      account: account,
      domain: host,
      verified: false,
      apex: LOCALHOST_DOMAINS.include?(host),
      redirect_for_name: nil
    )

    return unless domain.apex?

    # for development - only creating second domain for apexes.
    # If I wasn't lazy - I'd detect "www" domains and do the opposite, too.
    Domain.create!(
      account: account,
      domain: "www.#{host}",
      verified: false,
      apex: false,
      redirect_for_name: host
    )
  end

  def update_verification_status(trigger_verification: false) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if verified

    if Rails.env.development? && Domain.localhost_domain?(domain)
      update!(verified: true) if created_at < 10.seconds.ago
      return
    end

    trigger_dns_verification if trigger_verification

    response = Domain.render_service_request("/#{domain}", Net::HTTP::Get)
    if response.code == '429'
      raise RenderRateLimitError,
            "Render rate limit reached while reading domain #{domain} - code 429 \"#{response.body}\""
    end

    unless response.code == '200'
      raise "Error reading domain #{domain} in Render - code #{response.code} \"#{response.body}\""
    end

    body = JSON.parse(response.read_body)
    return if body['verificationStatus'] != 'verified'

    begin
      liveness_check
    rescue StandardError => e
      Honeybadger.notify("Error checking liveness of #{domain} - #{e}")
      return
    end

    update!(verified: true)
  end

  def self.render_service_request(path, method, body = nil) # rubocop:disable Metrics/AbcSize
    url = URI("https://api.render.com/v1/services/#{Rails.configuration.render[:service]}/custom-domains#{path}")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = method.new(url)
    request['Accept'] = 'application/json'
    request['Content-Type'] = 'application/json' if body.present?
    request['Authorization'] = "Bearer #{Rails.configuration.render[:api_key]}"
    request.body = body

    http.request(request)
  end

  private

  def trigger_dns_verification
    response = Domain.render_service_request("/#{domain}/verify", Net::HTTP::Post)
    return if response.code == '202'

    message = "Error triggering verification for domain #{domain} in Render - " \
              "code #{response.code} \"#{response.body}\""
    raise RenderRateLimitError, message if response.code == '429'

    raise message
  end

  def downcase_domain
    self.domain = domain.downcase
  end

  def destroy_in_render
    return if redirect_for_name.present?
    return if Rails.env.development? && Domain.localhost_domain?(domain)

    response = Domain.render_service_request("/#{domain}", Net::HTTP::Delete)

    return if response.code == '204'

    raise "Error deleting domain #{domain} in Render - code #{response.code} \"#{response.body}\""
  end

  def liveness_check
    url = URI("https://#{domain}/.postcard")
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(url)
    http.request(request)
  end

  def post_verification_tasks
    return unless verified
    return if account.unverified_domain?

    AccountMailer.domain_verified(account).deliver_later
    PingSearchEnginesJob.set(wait: 1.hour).perform_later account
  end
end
