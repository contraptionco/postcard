# frozen_string_literal: true

class UnsubscriptionController < ApplicationController
  before_action :set_email_message, :set_account

  def show; end

  def destroy
    raise 'cannot find subscription for unsubscription' if @email_message.subscription.blank?

    @email_message.update(triggered_unsubscribe: true)
    @email_message.subscription.unsubscribe!

    redirect_to '/', notice: 'You have unsubscribed!', status: :see_other
  end

  private

  def set_email_message
    @email_message = EmailMessage.find_by(unsubscribe_token: params[:token])
  end
end
