# frozen_string_literal: true

module Admin
  class AccountsController < ApplicationController
    prepend_before_action :authenticate_account!
    before_action :require_admin!
    skip_after_action :track_action
    layout 'dashboard_container'

    def search
      @account = current_account
      @query = request.post? && params[:account_email].is_a?(String) ? params[:account_email].strip.downcase : ''
      @found_account = Account.find_by(email: @query) if @query.present?
    end

    private

    def require_admin!
      head :forbidden unless current_account&.admin?
    end
  end
end
