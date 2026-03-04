# frozen_string_literal: true
# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy
# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, "https://fonts.gstatic.com", :data
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none
    policy.script_src  :self, :strict_dynamic
    policy.style_src   :self, "https://fonts.googleapis.com", :unsafe_inline
    policy.connect_src :self, :https
    policy.frame_src   :self, "https://tally.so"
    policy.base_uri    :self
    policy.form_action :self

    # Specify URI for violation reports
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted importmap and inline scripts
  # Required for Turbo/Stimulus and importmap-rails
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report CSP violations to a specified URI. See:
  # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy-Report-Only
  # config.content_security_policy_report_only = true
end
