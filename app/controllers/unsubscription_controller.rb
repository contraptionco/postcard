# frozen_string_literal: true

class UnsubscriptionController < ApplicationController
  before_action :set_email_message

  def show; end

  def destroy
    EmailMessage.transaction do
      @email_message.subscription&.unsubscribe!
      @email_message.update!(triggered_unsubscribe: true)
    end

    redirect_to '/', notice: 'You have unsubscribed!', status: :see_other
  end

  private

  def set_email_message
    @email_message = EmailMessage.find_by(unsubscribe_token: params[:token]) if params[:token].present?
    render :invalid_token, status: :not_found unless @email_message
  end
end
