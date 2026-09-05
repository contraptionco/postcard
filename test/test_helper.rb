# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
require_relative 'coverage' if ENV['COVERAGE'] == '1'
require 'webmock/minitest'

# An unexpected HTTP request is a missing test double, not a reason to contact
# a real mail, billing, domain, enrichment, or telemetry service.
WebMock.disable_net_connect!

require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  fixtures :all

  setup do
    # Premailer fetches the default mail font while rendering. Keep real mail
    # templates usable offline without permitting other outgoing HTTP requests.
    stub_request(:get, 'https://fonts.googleapis.com/css2?display=swap&family=Inter:wght@100..900')
      .to_return(status: 200, body: '', headers: { 'Content-Type' => 'text/css' })
  end
end
