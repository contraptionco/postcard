# frozen_string_literal: true

class AccountController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path

  def update
    @old_pinned_post = @account.pinned_post

    @account.update!(account_params)

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
      return redirect_to edit_page_path(@account),
                         alert: "The confirmation didn't match #{@account.postcard_host}, so your account was not deleted."
    end

    begin
      cancel_billing
    rescue Pay::Error => e
      Rails.logger.error "Failed to cancel billing while deleting account #{@account.id}: #{e.message}"
      return redirect_to edit_page_path(@account),
                         alert: 'We could not cancel your billing subscription, so your account was not deleted. Please contact support.'
    end

    @account.destroy!
    sign_out @account
    redirect_to root_path, notice: 'Your account and all of its data have been permanently deleted.'
  end

  private

  def confirmation_matches?
    params[:confirmation].to_s.strip.downcase == @account.postcard_host.downcase
  end

  # Destroying Pay::Customer records cascades to Pay::Subscription, whose
  # before_destroy cancels any active subscription at the payment processor.
  def cancel_billing
    @account.pay_customers.each(&:destroy!)
  end

  def account_params
    params.require(:account).permit(:pinned_post_id)
  end
end
