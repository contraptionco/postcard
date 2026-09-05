# frozen_string_literal: true

xml.instruct! :xml, :version => '1.0'
xml.tag! 'urlset', 'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9',
                    'xmlns:image' => 'http://www.google.com/schemas/sitemap-image/1.1', 'xmlns:video' => 'http://www.google.com/schemas/sitemap-video/1.1' do
  xml.url do
    xml.loc root_url(domain: @account.host, protocol: request.protocol)
  end

  if @account.show_posts_page? && @posts.publicly_listed.exists?
    xml.url do
      xml.loc public_posts_url(domain: @account.host, protocol: request.protocol)
    end
  end

  @posts.each do |post|
    xml.url do
      xml.loc public_post_url(post, domain: @account.host, protocol: request.protocol)
      xml.lastmod post.updated_at.xmlschema
    end
  end
end
