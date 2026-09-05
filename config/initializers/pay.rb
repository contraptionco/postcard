# frozen_string_literal: true

# Backport Pay's Rails 7.2 secrets compatibility fix until Pay is upgraded.
# https://github.com/pay-rails/pay/pull/834
module Pay
  module Env
    private

    def secrets
      Rails.application.secrets if Rails.application.respond_to?(:secrets)
    end
  end
end

Pay.setup do |config|
  # For use in the receipt/refund/renewal mailers
  config.business_name = 'Contraption Co. LLC'
  config.business_address = '169 Madison Ave #2174, New York, NY 10016'
  config.application_name = 'Postcard'
  config.support_email = 'postcard@contraption.co'

  config.default_product_name = 'Postcard'
  config.default_plan_name = 'postcard'

  config.automount_routes = false

  config.emails.payment_action_required = false
  config.emails.receipt = false
  config.emails.refund = false
  config.emails.subscription_renewing = false
end
