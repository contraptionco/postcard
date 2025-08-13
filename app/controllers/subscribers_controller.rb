# frozen_string_literal: true

require 'csv'

class SubscribersController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path
  before_action :set_subscription, only: %i[destroy]
  layout 'dashboard_container'

  def index
    @active_subscriptions = @account.subscriptions.active
  end

  def export
    respond_to do |format|
      format.csv do
        response.headers['Content-Type'] = 'text/csv'
        response.headers['Content-Disposition'] =
          "attachment; filename=#{@account.slug}-subscribers-#{Time.zone.now.to_fs(:iso8601)}.csv"
      end
    end
  end

  def destroy
    @subscription.unsubscribe!
    respond_to do |format|
      format.html { redirect_to page_subscribers_path(@account), notice: 'Subscriber deleted', status: :see_other }
    end
  end

  private

  def set_subscription
    @subscription = @account.subscriptions.find(params[:id])
  end
end
