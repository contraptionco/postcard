# frozen_string_literal: true

class SetupController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path
  before_action :redirect_in_solo

  include Wicked::Wizard

  steps :domain, :domain_purchase, :domain_hosted, :domain_connect, :domain_configure, :denouement

  def show # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity, Metrics/AbcSize
    if !@account.active_subscription? && %i[domain_connect domain_purchase].include?(step) && !params.key?(:session_id)
      return redirect_to @account.checkout_url(page_setup_url(@account, step), page_setup_url(@account, :domain)),
                         status: :found, allow_other_host: true
    end

    if @account.domains.any? && %i[domain domain_connect domain_purchase].include?(step)
      return redirect_to page_path(@account)
    end

    case step
    when :domain_purchase
      if request.params[:domain].present?
        new_domain = request.params[:domain].downcase.strip
        ahoy.track('domain_purchase', { domain: new_domain })
        add_domain(new_domain)
        return redirect_to page_setup_path(@account, :denouement)
      end
    when :domain_connect, :domain_purchase # rubocop:disable Lint/DuplicateCaseCondition
      return redirect_to page_setup_path(@account, :domain) if @account.domains.any?
    when :domain_configure
      return redirect_to page_setup_path(@account, :domain) unless @account.unverified_domain?

      begin
        record = Whois.whois(@account.apex_domain)
        parser = record.parser
        @registrar = parser.registrar
      rescue StandardError
        @registrar = nil
      end
    end

    render_wizard(nil, layout: 'whole_page')
  end

  def update # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    case step
    when :domain_hosted
      unless @account.update(account_params)
        # FriendlyId restores the persisted slug after validation fails.
        @account.slug = account_params[:slug] if account_params.key?(:slug)
        return render :domain_hosted, layout: 'whole_page', status: :unprocessable_entity
      end
      return redirect_to page_setup_path(@account, :denouement)
    when :domain_connect
      if request.params[:domain].present?
        new_domain = request.params[:domain].downcase.strip
        ahoy.track('domain_connect', { domain: new_domain })
        add_domain(new_domain)
        return redirect_to page_setup_path(@account, :domain_configure)
      end
      return redirect_to page_setup_path(@account, :domain_connect)
    when :domain_configure
      @account.domains.map(&:destroy)
      @account.reload
      return redirect_to page_setup_path(@account, :domain)
    end

    render_wizard @account
  end

  private

  def redirect_in_solo
    redirect_to page_path(@account) if Rails.configuration.solo_mode
  end

  def add_domain(new_domain)
    @account.domains.map(&:destroy)
    @account.reload
    Domain.register(@account, new_domain)
  end

  def account_params
    params.require(:account).permit(:name, :slug, :photo, :cover, :description, :accent_color, :code)
  end
end
