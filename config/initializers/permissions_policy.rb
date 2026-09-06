# frozen_string_literal: true

# Rails' permissions_policy DSL still emits the older Feature-Policy header.
# Use the current Permissions-Policy syntax for browser enforcement.
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Permissions-Policy
#
# Postcard does not use device sensors, media capture, location or hardware APIs.
# Keep media playback, fullscreen and payment at browser defaults so authors can
# explicitly delegate them to embeds through their iframe allow attributes.
Rails.application.config.action_dispatch.default_headers['Permissions-Policy'] =
  'accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), usb=()'
