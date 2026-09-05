# frozen_string_literal: true

class PagesController < ApplicationController
  prepend_before_action :authenticate_account!
  include PaymentRequired
  before_action :set_account
  layout 'dashboard'

  def show
    @email_address = EmailAddress.new
  end

  def edit; end

  def update
    respond_to do |format|
      if @account.update(account_params)
        @account.generate_icon
        format.html { redirect_to page_path(@account), notice: 'Page update published' }
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  private

  def account_params
    params.require(:account).permit(:name, :slug, :photo, :cover, :description, :accent_color, :code)
  end

  def set_account
    @account = Account.friendly.find(params[:slug])

    redirect_to page_path(current_account) unless @account == current_account || current_account&.admin?
  end
end
