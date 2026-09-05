# frozen_string_literal: true

class ShowcaseController < ApplicationController
  prepend_before_action :authenticate_account!
  include PaymentRequired
  before_action :set_account_from_path
  layout 'dashboard_container'

  SHOWCASED_PAGE_SLUGS = %w[
    kumar
    emma-lawler
    philipithomas
    ivanachen
    ericoneil
    victoria-martinez-de-la-cruz
    aaron-cohn
    jackohara
    mairin
    jj
    sinan-ozdemir
    chloe-mosundu-tanongku
    bittergiantsfan
    lily-wang
    hill-here
    jopie
    kaley-wendorf
    david-hagan
    matt-mayo
    doug-mellon
    lindsaycrouse
    joedaft
    andria-tomlin
  ].freeze

  def index
    @showcases = if Rails.env.production?
                   Rails.cache.fetch('app-showcases', expires_in: 1.hour) do
                     Account.where(slug: SHOWCASED_PAGE_SLUGS).to_a.shuffle
                   end
                 else
                   Account.order(created_at: :desc).limit(20).all
                 end
  end
end
