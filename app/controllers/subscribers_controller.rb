# frozen_string_literal: true

require 'csv'

class SubscribersController < ApplicationController
  PER_PAGE = 50

  prepend_before_action :authenticate_account!
  include PaymentRequired
  before_action :set_account_from_path
  layout 'dashboard_container'

  def index
    @query = params[:q].to_s.strip
    subscriptions = @account.subscriptions.active
    @total_subscribers = subscriptions.count
    if @query.present?
      subscriptions = subscriptions.joins(:email_address)
                                   .where('email_addresses.email ILIKE ?', "%#{Subscription.sanitize_sql_like(@query)}%")
    end
    @matching_subscribers = @query.present? ? subscriptions.count : @total_subscribers
    @total_pages = [(@matching_subscribers.to_f / PER_PAGE).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @active_subscriptions = subscriptions.includes(:email_address).order(id: :desc)
                                         .offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  def destroy
    subscription = @account.subscriptions.find(params[:id])
    subscription.unsubscribe!

    redirect_to page_subscribers_path(@account, q: params[:q].presence, page: params[:page].presence),
                notice: 'Subscriber removed. They will no longer receive your posts.', status: :see_other
  end

  def export
    respond_to do |format|
      format.csv do
        @export_subscriptions = @account.subscriptions.export.includes(:email_address)
        response.headers['Content-Type'] = 'text/csv'
        response.headers['Content-Disposition'] =
          "attachment; filename=#{@account.slug}-subscribers-#{Time.zone.now.to_fs(:iso8601)}.csv"
      end
    end
  end
end
