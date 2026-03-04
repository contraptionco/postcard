# frozen_string_literal: true

class UnsubscriptionController < ApplicationController
  before_action :set_email_message, :set_account
  before_action :require_email_message

  def show; end

  def invalid_token; end

  def destroy
    raise 'cannot find subscription for unsubscription' if @email_message.subscription.blank?

    @email_message.update(triggered_unsubscribe: true)
    @email_message.subscription.update(unsubscribed_at: Time.zone.now)

    redirect_to '/', notice: 'You have unsubscribed!', status: :see_other
  end

  private

  def set_email_message
    @email_message = EmailMessage.find_by(unsubscribe_token: params[:token])
  end

  def require_email_message
    return if @email_message.present?

    render :invalid_token, status: :not_found
  end
end
