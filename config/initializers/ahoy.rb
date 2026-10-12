# frozen_string_literal: true

module Ahoy
  class Store < Ahoy::DatabaseStore
  end
end

Ahoy.api = true
Ahoy.geocode = true
Ahoy.job_queue = :low
Ahoy.user_method = :current_account
Ahoy.cookies = :none
Ahoy.mask_ips = true
Ahoy.exclude_method = lambda do |_controller, request|
  # Only exclude CDN requests in multiuser mode when using a separate CDN subdomain
  Rails.configuration.multiuser_mode &&
    request.host == Rails.configuration.cdn_host &&
    Rails.configuration.cdn_host != Rails.configuration.base_host
end

Rails.application.config.to_prepare do
  Ahoy::BaseController.include(AhoyReadOnlySession)
end
