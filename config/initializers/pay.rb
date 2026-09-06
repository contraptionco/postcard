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
  config.enabled_processors = [:stripe]

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

# Backport CVE-2023-30614 without changing the Pay 5 billing schema.
# Remove this when upgrading Pay to a release with the upstream fix:
# https://github.com/pay-rails/pay/commit/5d6283a24062bd272a524ec48415f536a67ad57f
module PostcardPayPaymentRedirect
  def show
    params[:back] = safe_payment_return_path(params[:back])
    super
  end

  private

  def safe_payment_return_path(value)
    return '/' unless value.is_a?(String)
    return '/' if value.match?(/[\\\x00-\x20\x7f]/)

    uri = URI.parse(value)
    return '/' if uri.scheme || uri.host
    return '/' unless value.start_with?('/') && !value.start_with?('//')

    value
  rescue URI::InvalidURIError
    '/'
  end
end

Rails.application.config.to_prepare do
  Pay::PaymentsController.prepend(PostcardPayPaymentRedirect)
end
