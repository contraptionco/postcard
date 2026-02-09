# frozen_string_literal: true

class GoogleOneTapController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:callback]

  def callback
    validator = GoogleIDToken::Validator.new
    payload = validator.check(params[:credential], Rails.configuration.google_oauth[:client_id])

    if payload.nil?
      redirect_to new_account_session_path, alert: 'Google authentication failed.'
      return
    end

    account = find_or_create_account(payload)

    if account.present? && account.persisted?
      sign_in(account)
      redirect_to after_sign_in_path, notice: 'Signed in with Google.'
    else
      redirect_to new_account_session_path, alert: 'Could not create account.'
    end
  rescue GoogleIDToken::ValidationError => e
    Rails.logger.error "Google One Tap validation error: #{e.message}"
    redirect_to new_account_session_path, alert: 'Google authentication failed.'
  end

  private

  def find_or_create_account(payload)
    email = payload['email']
    return nil unless payload['email_verified']

    account = Account.find_by(email: email)
    return account if account.present?

    # Create new account
    Account.create(
      email: email,
      name: payload['name'],
      password: Devise.friendly_token[0, 20]
    ).tap do |new_account|
      if new_account.persisted?
        attach_photo_from_google(new_account, payload['picture'])
        new_account.enrich
        SubscribeToContraptionGhostJob.perform_later(new_account.email, new_account.name)
      end
    end
  end

  def attach_photo_from_google(account, picture_url)
    return if picture_url.blank?

    account.attach_photo_from_url(picture_url)
  rescue StandardError => e
    Rails.logger.error "Failed to attach Google photo: #{e.message}"
  end

  def after_sign_in_path
    stored_location_for(:account) || page_path(current_account)
  end
end
