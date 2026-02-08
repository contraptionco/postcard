# frozen_string_literal: true

module Admin
  class AccountsController < ApplicationController
    prepend_before_action :authenticate_account!
    before_action :require_admin!

    def search
      @query = params[:q]
      @account = Account.find_by(email: @query) if @query.present?
    end

    private

    def require_admin!
      return if current_account&.admin?

      redirect_to root_path, alert: 'Access denied.'
    end
  end
end
