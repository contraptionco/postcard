# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin 'application', preload: true
pin 'dashboard'
pin '@hotwired/turbo-rails', to: 'turbo.min.js', preload: true
pin '@hotwired/stimulus', to: '@hotwired--stimulus.js', preload: true # @3.2.1
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js', preload: true
pin_all_from 'app/javascript/controllers', under: 'controllers', preload: true
pin '@rails/actiontext', to: 'actiontext.js'
pin 'tailwindcss-stimulus-components' # @3.0.4
pin 'ahoy.js', preload: true # @0.4.0
pin 'clipboard' # @2.0.11
pin 'stimulus-notification', preload: true # @2.1.0
pin '@rails/activestorage', to: '@rails--activestorage.js' # @7.0.4
pin 'local-time-cdn' # @2.1.0
pin 'lodash.debounce' # @4.0.8
pin 'stimulus-dropdown' # @2.1.0
pin 'stimulus-use', preload: true # @0.51.3
pin 'hotkeys-js' # @3.10.1
# Use the patched editor tracked by the action_text-trix gem and bundle audit.
pin 'trix', to: 'trix.js'
