# frozen_string_literal: true

class PublicPostsController < ApplicationController
  before_action :redirect_if_host_changed, :suppress_if_banned, :ensure_account_exists # TODO: - redirect_if_slug_changed
  before_action :set_post, except: :index

  def index
    @email_address = EmailAddress.new
    @posts = @account.posts.published.publicly_listed
    @latest_post = @posts.first

    respond_to do |format|
      format.html do
        redirect_to @account.url unless @account.show_posts_page?
      end
      format.rss { render :layout => false }
    end
  end

  def show
    @email_address = EmailAddress.new
    @page_title = @post.subject
  end

  def og_image
    # Include wabi_sabi_mode in cache key so toggling the setting busts the cache
    # Also include account.updated_at since images may have changed
    cache_key = "post-#{@post.id}-#{@post.updated_at.to_i}-#{@account.updated_at.to_i}-wabi-#{@account.wabi_sabi_mode}-og-img-v1"
    png = Rails.cache.fetch(cache_key) do
      generate_og_image
    end

    expires_in 24.hours, public: true if @account.updated_at.to_i == params[:updated_at].to_i
    send_data(png, type: 'image/png', disposition: 'inline')
  end

  private

  def generate_og_image
    relative_html = render_to_string({
                                       template: 'public_posts/og_image',
                                       layout: 'application',
                                       locals: { :account => @account, :post => @post, request: request }
                                     })

    grover = Grover.new(
      Grover::HTMLPreprocessor.process(relative_html, "#{request.base_url}/", request.protocol)
    )

    grover.to_png
  end

  def set_post
    @post = @account.posts.published.friendly.find(params[:slug])

    return if @post.slug == params[:slug]

    redirect_to public_post_url(@post, domain: @post.account.host, protocol: request.protocol),
                status: :moved_permanently, allow_other_host: true
  end
end
