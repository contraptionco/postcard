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
      format.md { render plain: posts_index_markdown, content_type: 'text/markdown' }
    end
  end

  def show
    @email_address = EmailAddress.new
    @page_title = @post.subject

    respond_to do |format|
      format.html
      format.md { render plain: post_markdown(@post), content_type: 'text/markdown' }
    end
  end

  def og_image
    png = Rails.cache.fetch("post-#{@post.id}-#{@post.updated_at.to_i}-og-img-v0") do
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

  def post_markdown(post)
    body_markdown = ReverseMarkdown.convert(post.body.to_s, unknown_tags: :bypass)
    <<~MD
      # #{post.subject}

      *Permalink: #{post.url}*

      *Published: #{post.published_at.strftime('%Y-%m-%d')}*

      #{body_markdown}
    MD
  end

  def posts_index_markdown
    lines = ["# #{@account.name} - Posts\n\n"]
    @posts.each do |post|
      lines << "- [#{post.subject}](#{post.url}.md) (#{post.published_at.strftime('%Y-%m-%d')})"
    end
    lines.join("\n")
  end
end
