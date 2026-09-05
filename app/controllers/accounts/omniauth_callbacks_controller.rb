# frozen_string_literal: true

module Accounts
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      account = Account.from_omniauth(auth)

      if account.present?
        sign_out_all_scopes
        flash[:success] = t 'devise.omniauth_callbacks.success', kind: 'Google'
        sign_in_and_redirect account, event: :authentication
      else
        flash[:alert] =
          t 'devise.omniauth_callbacks.failure', kind: 'Google', reason: "#{auth.info.email} is not authorized."
        redirect_to new_account_session_path
      end
    end

    def after_sign_in_path_for(resource_or_scope)
      stored = stored_location_for(resource_or_scope)
      return stored if stored.present?
      return page_checkout_path(resource_or_scope) if resource_or_scope.is_a?(Account) && resource_or_scope.requires_payment?

      root_path
    end

    private

    def auth
      @auth ||= request.env['omniauth.auth']
    end

    protected

    def after_omniauth_failure_path_for(_scope)
      new_account_session_path
    end
  end
end
