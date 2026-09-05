# frozen_string_literal: true

module Admin
  class AccountsController < ApplicationController
    prepend_before_action :authenticate_account!
    before_action :require_admin!
    layout 'dashboard_container'

    def search
      @account = current_account
      @query = params[:q].is_a?(String) ? params[:q].strip.downcase : ''
      @found_account = Account.find_by(email: @query) if @query.present?
    end

    private

    def require_admin!
      head :forbidden unless current_account&.admin?
    end
  end
end
