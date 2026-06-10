# frozen_string_literal: true

class SupportController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path
  before_action :redirect_in_solo
  layout 'dashboard'

  def show; end

  private

  def redirect_in_solo
    redirect_to page_path(@account) if Rails.configuration.solo_mode
  end
end
