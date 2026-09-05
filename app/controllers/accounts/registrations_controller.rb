# frozen_string_literal: true

module Accounts
  class RegistrationsController < Devise::RegistrationsController
    prepend_before_action :check_captcha, only: [:create]
    before_action :ensure_signup_allowed, only: %i[new create]

    def create
      build_resource(sign_up_params)
      resource.save
      yield resource if block_given?
      if resource.persisted?
        # Handle newsletter subscription based on checkbox
        if params[:account][:subscribe_to_newsletter] == '1'
          SubscribeToContraptionGhostJob.perform_later(resource.email, resource.name)
        end
        
        if resource.active_for_authentication?
          set_flash_message! :notice, :signed_up
          sign_up(resource_name, resource)
          respond_with resource, location: after_sign_up_path_for(resource)
        else
          set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
          expire_data_after_sign_up!
          respond_with resource, location: after_inactive_sign_up_path_for(resource)
        end
      else
        clean_up_passwords resource
        set_minimum_password_length
        respond_with resource
      end
      
      current_account.update(admin: true) if current_account&.persisted? && Rails.configuration.solo_mode && Account.count == 1
      current_account.enrich if current_account&.persisted?
    end

    # In multiuser mode, account deletion goes through AccountController#destroy,
    # which requires typed confirmation and cancels billing first.
    def destroy
      if Rails.configuration.multiuser_mode
        redirect_to page_support_path(current_account),
                    notice: 'To delete your account, use the "Delete account" section on the support page.'
      else
        super
      end
    end

    def after_sign_up_path_for(account)
      if Rails.configuration.multiuser_mode
        page_checkout_path(account)
      else
        page_path(account)
      end
    end

    private

    def check_captcha
      return if verify_recaptcha

      self.resource = resource_class.new sign_up_params
      resource.validate # Look for any other validation errors besides reCAPTCHA
      set_minimum_password_length

      respond_with_navigational(resource) do
        flash.discard(:recaptcha_error) # We need to discard flash to avoid showing it on the next page reload
        render :new
      end
    end

    def ensure_signup_allowed
      return unless Rails.configuration.solo_mode
      redirect_to root_path if Account.exists?
    end

    def sign_up_params
      params.require(:account).permit(:name, :email, :password)
    end
  end
end
