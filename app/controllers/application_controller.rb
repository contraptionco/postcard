# frozen_string_literal: true

class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_account
  after_action :track_action

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
  end

  AUTOTRACK_EVENT = 'autotrack'
  def track_action
    ahoy.track AUTOTRACK_EVENT, request.path_parameters.merge({
                                                                url: request.original_url,
                                                                method: request.method,
                                                                canonical_url: request.original_url.split('?').first,
                                                                domain: request.host,
                                                                account: @account&.id
                                                              })
  end

  def set_account
    if Rails.configuration.solo_mode
      @account = Account.first
      return
    end

    return set_account_from_subdomain if postcard_subdomain?

    set_account_from_custom_domain
  end

  private

  def postcard_subdomain?
    request.host.ends_with?(".#{Rails.configuration.base_host}")
  end

  def account_slug
    request.host.chomp(".#{Rails.configuration.base_host}").downcase
  end

  def redirect_if_host_changed # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # Handle common scenarios to avoid hitting db
    return if @account.blank?
    return if @account.domains.count.zero? && postcard_subdomain? && @account.slug == account_slug
    return if @account.host == request.host
    return if @account.unverified_domain?

    current_domain = @account.domains.find_by(domain: request.host)
    if current_domain.present?
      return rewrite_host_and_redirect(current_domain.redirect_for_name) if current_domain&.redirect_for_name.present?

      return # on custom domain
    end

    rewrite_host_and_redirect(@account.host)
  end

  def rewrite_host_and_redirect(new_host)
    destination = URI.parse(request.url)
    destination.host = new_host
    redirect_to String(destination), allow_other_host: true
  end

  def set_account_from_path
    @account = Account.friendly.find(params[:page_slug])

    redirect_to page_path(current_account) unless @account == current_account || current_account&.admin?
  end

  def set_account_from_subdomain
    @account = Account.with_all_rich_text.friendly.find(account_slug)
  end

  def set_account_from_custom_domain
    @account = Account.with_rich_text_description.joins(:domains).find_by(domains: { domain: request.host })
  end

  def ensure_account_exists
    return unless Rails.configuration.solo_mode
    return if Account.exists?

    redirect_to new_account_registration_path
  end

  def suppress_if_banned
    render file: 'public/403.html', status: :forbidden, layout: :default if @account&.locked_at.present?
  end

end
