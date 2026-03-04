# frozen_string_literal: true

# Define an application-wide HTTP permissions policy. For further
# information see https://developers.google.com/web/updates/2018/06/feature-policy
#
# This policy restricts access to browser APIs that this application does not use,
# reducing the attack surface and improving security.

Rails.application.config.permissions_policy do |f|
  # Disable access to sensors
  f.accelerometer      :none
  f.gyroscope          :none
  f.magnetometer       :none
  f.ambient_light_sensor :none

  # Disable access to media devices
  f.camera             :none
  f.microphone         :none

  # Disable access to location
  f.geolocation        :none

  # Disable access to hardware
  f.usb                :none
  f.midi               :none

  # Disable payment and identity APIs
  f.payment            :none

  # Disable autoplay and picture-in-picture
  f.autoplay           :none
  f.picture_in_picture :none

  # Disable VR/XR features
  f.xr_spatial_tracking :none

  # Allow fullscreen only from same origin (for viewing postcards)
  f.fullscreen         :self

  # Disable interest-based advertising features
  f.interest_cohort    :none
end
