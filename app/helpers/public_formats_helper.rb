# frozen_string_literal: true

module PublicFormatsHelper
  def public_posts_feed_url(account)
    public_posts_url(public_format_options(account).merge(format: :rss))
  end

  def public_posts_markdown_url(account)
    public_posts_url(public_format_options(account).merge(format: :md))
  end

  def public_post_markdown_url(post)
    public_post_url(post, public_format_options(post.account).merge(format: :md))
  end

  private

  def public_format_options(account)
    { host: account.host, protocol: request.protocol, port: request.port }
  end
end
