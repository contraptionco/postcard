# frozen_string_literal: true

module PaymentRequired
  extend ActiveSupport::Concern

  included do
    before_action :require_payment
  end

  private

  def require_payment
    return unless current_account&.requires_payment?
    return if params.key?(:session_id) # Just returned from Stripe, webhook pending

    redirect_to page_checkout_path(current_account)
  end
end
