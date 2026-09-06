# frozen_string_literal: true

require 'simplecov'
require 'simplecov_json_formatter'

SimpleCov.start 'rails' do
  mode = ENV.fetch('APP_MODE', 'SOLO').upcase
  command_name "rails-#{mode}"
  coverage_dir "coverage/#{mode}"
  enable_coverage :branch
  track_files '{app,lib}/**/*.rb'
  # Each mode reports this run only; stale local results cannot inflate coverage.
  use_merging false
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])
end
