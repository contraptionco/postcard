# frozen_string_literal: true

class AccountController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path

  def update
    @old_pinned_post = @account.pinned_post

    unless @account.update(account_params)
      return render plain: @account.errors.full_messages.to_sentence, status: :unprocessable_entity
    end

    respond_to do |format|
      format.html { redirect_to page_posts_path(@account), notice: 'Success', status: :see_other }
      format.turbo_stream
    end
  end

  def destroy
    unless Rails.configuration.multiuser_mode
      return redirect_to page_path(@account), alert: 'Account deletion is not available in solo mode.'
    end
    unless @account == current_account
      return redirect_to page_path(current_account), alert: 'You can only delete your own account.'
    end
    unless confirmation_matches?
      return redirect_to page_support_path(@account),
                         alert: "The confirmation didn't match #{@account.postcard_host}, so your account was not deleted."
    end

    begin
      cancel_billing
    rescue Pay::Error, ::Stripe::StripeError => e
      Rails.logger.error "Failed to cancel billing while deleting account #{@account.id}: #{e.message}"
      return redirect_to page_support_path(@account),
                         alert: 'We could not cancel your billing subscription, so your account was not deleted. Please contact support.'
    end

    # Lock the account so sign-in is blocked and the public page goes offline
    # immediately, then delete the data in the background — established
    # accounts have too many analytics, subscriber, and email rows to delete
    # within a request.
    @account.lock_access!
    DestroyAccountJob.perform_later(@account)
    sign_out @account
    redirect_to root_path,
                notice: 'Your account has been deleted. Your page is now offline, and all of your data will be removed shortly.'
  end

  private

  def confirmation_matches?
    params[:confirmation].to_s.strip.downcase == @account.postcard_host.downcase
  end

  # Deleting the customer at Stripe immediately cancels ALL of their
  # subscriptions, including past_due ones that Pay's cancel helpers skip, and
  # scrubs the customer's details from Stripe. This must happen synchronously:
  # Pay's own cancel-on-destroy callback swallows API errors, which could
  # leave a subscription billing forever with no local record of it.
  def cancel_billing
    @account.pay_customers.each do |pay_customer|
      delete_stripe_customer(pay_customer)

      # Keep local records consistent so Pay's cancel-on-destroy callback
      # doesn't make a doomed API call when DestroyAccountJob removes them.
      pay_customer.subscriptions.active.each do |subscription|
        subscription.update!(status: 'canceled', ends_at: Time.current)
      end
    end
  end

  def delete_stripe_customer(pay_customer)
    return unless pay_customer.processor == 'stripe' && pay_customer.processor_id.present?

    ::Stripe::Customer.delete(pay_customer.processor_id)
  rescue ::Stripe::InvalidRequestError => e
    # Already deleted at Stripe — nothing left to cancel.
    raise unless e.message.include?('No such customer')
  end

  def account_params
    params.require(:account).permit(:pinned_post_id)
  end
end
