# frozen_string_literal: true

module Accounts
  class SessionsController < Devise::SessionsController
    # before_action :configure_sign_in_params, only: [:create]

    # GET /resource/sign_in
    # def new
    #   super
    # end

    # POST /resource/sign_in
    # def create
    #   super
    # end

    # DELETE /resource/sign_out
    # def destroy
    #   super
    # end

    # protected

    # If you have extra params to permit, append them to the sanitizer.
    # def configure_sign_in_params
    #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
    # end

    def after_sign_in_path_for(account)
      stored = stored_location_for(account)
      return stored if stored.present?
      return page_checkout_path(account) if account.is_a?(Account) && account.requires_payment?

      root_path
    end
  end
end
