# frozen_string_literal: true

module AhoyReadOnlySession
  extend ActiveSupport::Concern

  included do
    prepend_before_action :skip_analytics_session_cookie
  end

  private

  def skip_analytics_session_cookie
    # Analytics may read current_account, but a delayed response must not replace
    # a newer login session cookie (including OmniAuth's OAuth state).
    request.session_options[:skip] = true
  end
end
