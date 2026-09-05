# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.2'

gem 'ahoy_email', '~> 2.1', '>= 2.1.3'
gem 'ahoy_matey'
gem 'audited', '~> 5.0', '>= 5.0.2'
gem 'aws-sdk-s3'
gem 'bcrypt', '~> 3.1.7'
gem 'blazer'
gem 'clearbit', '~> 0.3.3'
gem 'dalli', '~> 3.2'
gem 'devise', '~> 4.9'
gem 'dotenv-rails', '~> 2.8'
gem 'friendly_id', '~> 5.4', '>= 5.4.2'
gem 'geocoder'
gem 'grover', '~> 1.1'
gem 'honeypot-captcha', '~> 1.0'
gem 'httparty', '~> 0.21.0'
gem 'image_processing', '~> 1.2'
gem 'importmap-rails', '~> 2'
gem 'inline_svg', '~> 1.8'
gem 'jbuilder'
gem 'local_time', '~> 2.1'
gem 'mailkick', '~> 1.0'
gem 'maxminddb'
gem 'meta-tags', '~> 2.18'
gem 'name_of_person', '~> 1.1'
gem 'omniauth', '~> 2.1'
gem 'omniauth-google-oauth2', '~> 1.1'
gem 'omniauth-rails_csrf_protection', '~> 1.0'
gem 'pay', '~> 5.0'
gem 'pg', '~> 1.1'
gem 'possessive', '~> 1.0'
gem 'aws-sdk-rails', '~> 5'
gem 'aws-actionmailer-ses', '~> 1'
gem 'premailer-rails', '~> 1.11'
gem 'puma', '~> 6.4'
gem 'rails', '~> 7.1'
gem 'rails_heroicon', '~> 2.1.0'
gem 'recaptcha'
gem 'redis', '~> 4.0'
gem 'ruby-vips', '~> 2.1'
gem 'sitemap_generator', '~> 6.3'
gem 'sprockets-rails'
gem 'stimulus-rails', '~> 1.2.1'
gem 'stripe', '~> 7.0'
gem 'tailwindcss-rails', '2.0.25'
gem 'truemail', '~> 2.7'
gem 'turbo-rails', '1.4.0'
gem 'twitter', '~> 7.0'
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]
gem 'wcag_color_contrast', '~> 0.1.0'
gem 'reverse_markdown', '~> 2.1'
gem 'whois', '~> 5.1'
gem 'whois-parser', '~> 2.0'
gem 'wicked', '~> 1.4'
gem "solid_cache", "~> 0.6.0"
gem "solid_queue", "~> 0.3.2"
gem "mission_control-jobs", "~> 0.2.1"
gem "health_check", "~> 3.1"
gem "pghero"

group :development, :test, :preview do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem 'brakeman', '~> 5.0'
  gem 'byebug', platforms: %i[mri mingw x64_mingw]
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'faker', '~> 2.19'
  gem 'rubocop', '~> 1.37'
  gem 'rubocop-faker', '~> 0.2.0'
  gem 'rubocop-rails', '~> 2.17.2'
  gem 'solargraph', '~> 0.44.2'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'web-console'

  # Email development tools
  gem 'letter_opener'
  gem 'letter_opener_web'

  # Add speed badges [https://github.com/MiniProfiler/rack-mini-profiler]
  # gem "rack-mini-profiler"

  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem 'capybara'
  gem 'selenium-webdriver'
  gem 'webdrivers'
end

group :production do
  gem "cloudflare-rails"
end
