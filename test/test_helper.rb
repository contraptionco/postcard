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
end
