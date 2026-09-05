# frozen_string_literal: true

class PublicPagesController < ApplicationController
  before_action :redirect_localhost_to_localtest_in_dev, :redirect_if_host_changed, :suppress_if_banned, :ensure_account_exists
  ALREADY_SUBSCRIBED_MESSAGE = 'You have already subscribed to this mailing list.'
  protect_from_forgery except: :create

  def show
    redirect_to '/', notice: 'Email confirmed!' if params[:verified]
    @email_address = EmailAddress.new
  end

  def create
    return redirect_to '/' unless verify_recaptcha

    @email_address = EmailAddress.find_or_create_by(email: (params.dig(:email_address, :email) || params[:email]).strip.downcase)
    return render :show, status: :bad_request unless @email_address.valid?

    @subscription = Subscription.create_with(source: :signup).find_or_create_by(email_address: @email_address,
                                                                                account: @account)

    return redirect_to '/', notice: ALREADY_SUBSCRIBED_MESSAGE if @subscription.active?

    @subscription.send_verification_email

    redirect_to '/', notice: 'Check your email for a verification link.'
  end

  def sitemap
    return head :not_found if @account.blank?

    @posts = @account.posts.published.publicly_indexable
  end

  def llms_txt
    return head :not_found if @account.blank?

    @posts = @account.posts.published.publicly_listed
    render plain: generate_llms_txt, content_type: 'text/plain'
  end

  def og_image
    png = Rails.cache.fetch("account-#{@account.id}-#{@account.updated_at.to_i}-og-img-v7") do
      generate_og_image
    end

    expires_in 24.hours, public: true if @account.updated_at.to_i == params[:updated_at].to_i
    send_data(png, type: 'image/png', disposition: 'inline')
  end

  private

  def generate_og_image
    relative_html = render_to_string({
                                       template: 'public_pages/og_image',
                                       layout: 'application',
                                       locals: { :account => @account, request: request }
                                     })

    grover = Grover.new(
      Grover::HTMLPreprocessor.process(relative_html, "#{request.base_url}/", request.protocol)
    )

    grover.to_png
  end

  def redirect_localhost_to_localtest_in_dev
    return unless Rails.env.development?
    return unless request.host == 'localhost'

    redirect_to "http://#{Rails.configuration.base_host}:3000#{request.path}",
                allow_other_host: true
  end

  def generate_llms_txt
    description_text = if @account.description.present?
                         ReverseMarkdown.convert(@account.description.to_s)
                       else
                         ''
                       end

    lines = [
      "# #{@account.name}",
      '',
      "#{description_text}".strip,
      '',
      "Homepage: #{@account.url}",
      ''
    ]

    if @posts.any?
      lines << '## Posts'
      lines << ''
      @posts.each do |post|
        lines << "- [#{post.subject}](#{post.url}.md)"
      end
    end

    lines.join("\n")
  end
end
