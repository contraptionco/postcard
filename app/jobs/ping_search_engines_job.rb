# frozen_string_literal: true

class PingSearchEnginesJob < RecordBatchJob
  queue_as :low

  def perform(*accounts)
    accounts.each do |account|
      SitemapGenerator::Sitemap.ping_search_engines("https://#{account.host}/sitemap.xml")
    end
  end
end
