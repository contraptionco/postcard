# frozen_string_literal: true

class Account < ApplicationRecord
  include Sluggable
  include Verifiable

  audited
  has_associated_audits
  pay_customer
  has_subscriptions

  visitable :ahoy_signup_visit

  enum source: { signup: 0 }, _prefix: true, _default: :signup

  has_many :visits, class_name: 'Ahoy::Visit', foreign_key: :user_id, dependent: :destroy, inverse_of: :account
  has_many :subscriptions, dependent: :destroy
  has_many :messages, class_name: 'EmailMessage', as: :user, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :subscribers_imports, dependent: :destroy
  has_many :feedbacks, dependent: :destroy
  belongs_to :pinned_post, class_name: 'Post', optional: true, inverse_of: :pinned_by

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :omniauthable, :lockable,
         omniauth_providers: [:google_oauth2]

  validates :name, presence: true, on: :update
  validate :email_is_valid, on: :create
  validates :name, presence: true
  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_nil: true
  VALID_SLUG_REGEX = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  validates :slug, presence: true, length: { minimum: 2, maximum: 255 },
                   format: { with: VALID_SLUG_REGEX, message: "can only contain letters, numbers and '-'" },
                   exclusion: { in: DISALLOWED_SLUGS },
                   uniqueness: true

  after_create_commit lambda {
    EnrichAccountJob.perform_later self unless Rails.env.test?
    register_first_sign_in_actions
  }

  before_save :downcase_slug
  before_save :set_random_accent_color
  before_destroy :unsubscribe_from_updates

  has_one_attached :photo do |attachable|
    attachable.variant :thumb, resize_to_fill: [800, 800, { crop: 'attention' }]
  end

  has_one_attached :cover

  has_one_attached :icon

  has_rich_text :description

  extend FriendlyId
  friendly_id :name, use: %i[slugged history]

  def to_param
    slug
  end

  def primary_custom_domain
    domains.each do |domain|
      return domain if domain.redirect_for_name.blank?
    end
    nil
  end

  def host(show_unverified: false)
    if domains.length.positive? && (primary_custom_domain.verified? || show_unverified)
      return primary_custom_domain.domain
    end

    Rails.configuration.solo_mode ? Rails.configuration.base_host : postcard_host
  end

  def pretty_host
    return host[4..] if host.starts_with?('www.')

    host
  end

  def postcard_host
    "#{slug}.#{Rails.configuration.base_host}"
  end

  def apex_domain
    domains.each do |domain|
      return domain.domain if domain.apex?
    end
  end

  def url(show_unverified: false)
    scheme = Rails.env.production? ? 'https' : 'http'
    port = Rails.env.production? ? nil : ':3000'
    domain_host = host(show_unverified: show_unverified)
    "#{scheme}://#{domain_host}#{port}"
  end

  MIN_CONTRAST_RATIO = 3.0
  LIGHT_LABEL_COLOR = '#FFFFFF'
  DARK_LABEL_COLOR = '#111111'

  def accent_color_has_sufficient_contrast_to_light(ratio = MIN_CONTRAST_RATIO)
    accent_color_contrast(LIGHT_LABEL_COLOR) > ratio
  end

  def accent_label_color
    return LIGHT_LABEL_COLOR if accent_color_contrast(LIGHT_LABEL_COLOR) > MIN_CONTRAST_RATIO
    return LIGHT_LABEL_COLOR if accent_color_contrast(LIGHT_LABEL_COLOR) > accent_color_contrast(DARK_LABEL_COLOR)

    DARK_LABEL_COLOR
  end

  def accent_color_rgb
    rgb = accent_color.match(/^#(..)(..)(..)$/).captures.map(&:hex)
    "rgb(#{rgb.join(', ')})"
  end

  def show_posts_page?
    posts.published.length > 1
  end

  def active_subscription?
    return true if Rails.configuration.solo_mode

    payment_processor&.subscribed?
  end

  def requires_payment?
    return false if Rails.configuration.solo_mode
    return false if grandfathered?
    return false if ever_subscribed?

    !payment_processor&.subscribed?
  end

  def ever_subscribed?
    Pay::Subscription.joins(:customer)
      .where(pay_customers: { owner_type: 'Account', owner_id: id })
      .exists?
  end

  def unverified_domain?
    domains.each do |domain|
      return true unless domain.verified?
    end
    false
  end

  def first_name
    name.present? ? NameOfPerson::PersonName.full(name).first : nil
  end

  def last_name
    name.present? ? NameOfPerson::PersonName.full(name).last : nil
  end

  def email_domain
    email.split('@').last.downcase
  end

  def enrich
    cover_photos = Dir.glob('app/assets/images/default_cover/*')
    cover.attach(io: File.open(cover_photos.sample), filename: 'cover.jpg') unless cover.attached?
  end

  def subscribe_to_updates
    updates = Account.find_by(slug: 'updates')
    return if updates.blank?

    # Ok if this fails
    Subscription.create_with(source: :signup, verified_at: Time.zone.now) \
                .where(account: updates, email_address: EmailAddress.find_or_create_by(email: email)) \
                .first_or_create
  end

  def unsubscribe_from_updates
    updates = Account.find_by(slug: 'updates')
    return if updates.blank?

    email_address = EmailAddress.find_by(email: email)
    return if email_address.blank?

    subscription = Subscription.find_by(account: updates, email_address: email_address)
    return if subscription.blank?

    subscription.destroy!
    Rails.logger.info "Unsubscribed #{email} from updates"
  end

  def generate_icon
    unless photo.attached?
      icon.purge if icon.attached?
      return
    end

    circle_mask = Vips::Image.svgload_buffer('<svg viewBox="0 0 800 800"><circle cx="400" cy="400" r="400"/></svg>')
    blob = Vips::Image.new_from_buffer(photo.download, '')
                      .thumbnail_image(800, height: 800, crop: :attention)
                      .composite(circle_mask, :dest_in)
                      .write_to_buffer('.png')
    icon.attach(io: StringIO.new(blob), filename: 'icon.png', content_type: 'image/png')
  end

  def checkout_url(success_url, cancel_url) # rubocop:disable Metrics/MethodLength
    raise 'Payments disabled in SOLO mode' if Rails.configuration.solo_mode

    set_payment_processor :stripe
    payment_processor.customer
    checkout_session = payment_processor.checkout(
      mode: 'subscription',
      line_items: [
        {
          price: Rails.configuration.stripe[:plan],
          quantity: 1
        }
      ],
      automatic_tax: { enabled: true },
      cancel_url: cancel_url,
      success_url: success_url,
      allow_promotion_codes: true,
      billing_address_collection: 'auto',
      payment_method_collection: 'if_required',
      subscription_data: { trial_period_days: 30 },
      customer_update: {
        address: 'auto',
        name: 'auto'
      }
    )
    checkout_session.url
  end

  def self.from_omniauth(auth) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
    if auth.info.email.blank?
      Rails.logger.error "No email address for #{auth.provider} user #{auth.uid}"
      return nil
    end
    if !auth.info.email_verified && auth.provider == 'google_oauth2'
      Rails.logger.error "Email address for #{auth.provider} user #{auth.uid} not verified"
      return nil
    end

    exists = Account.find_by(email: auth.info.email).present?

    account = where(email: auth.info.email).first_or_create do |a|
      a.email = auth.info.email
      a.password = Devise.friendly_token[0, 20]
      a.name = auth.info.name
    end

    unless exists
      SubscribeToContraptionGhostJob.perform_later(account.email, account.name)
    end
    if account.admin?
      Rails.logger.error "Admin account #{account.email} cannot use oauth to log in"
      raise 'Admins cannot use OAuth'
    end
    account.attach_photo_from_url(auth.info.image) if !account.photo.attached? && auth.info.image.present?
    account.enrich unless exists
    account
  end

  def attach_photo_from_url(url)
    filename = File.basename(URI.parse(url).path)
    file = URI.open(url) # rubocop:disable Security/Open

    photo.attach(io: file, filename: filename)
  end

  def attach_cover_from_url(url)
    filename = File.basename(URI.parse(url).path)
    file = URI.open(url) # rubocop:disable Security/Open

    cover.attach(io: file, filename: filename)
  end

  def page_visits(from: nil, to: nil)
    query = Ahoy::Event.where(name: ApplicationController::AUTOTRACK_EVENT) \
                       .where("ahoy_events.properties->>'domain' <> ?", Rails.configuration.base_host) \
                       .where("(ahoy_events.properties->>'account')::bigint = ?", id) \
                       .where("ahoy_events.properties->>'action' <> 'og_image'") \
                       .where("ahoy_events.properties->>'controller' <> 'robots'") \
                       .where("ahoy_events.properties->>'controller' <> 'sitemap'") \
                       .where('ahoy_events.user_id IS DISTINCT FROM ?', id)
    query = query.where('ahoy_events.time >= ?', from) if from
    query = query.where('ahoy_events.time <= ?', to) if to
    query
  end

  def register_first_sign_in_actions # rubocop:disable Metrics/AbcSize
    PostInAdminChatJob.perform_later "[New signup - #{self.email}] #{self.name} #{self.url}"
    PingSearchEnginesJob.set(wait: 24.hours).perform_later self
    AccountMailer.account_details(self).deliver_later(wait: 5.minutes)

    subscribe_to_updates
    register_lists
    register_welcome_emails
  end

  private

  def email_is_valid
    errors.add(email, "can't receive email") unless Truemail.valid?(email)
  end

  def downcase_slug
    self.slug = slug.downcase
  end

  RANDOM_ACCENT_COLORS = [
    '#2c6153',
    '#6a525a',
    '#0056ac'
  ].freeze
  def set_random_accent_color
    return unless accent_color.nil?

    self.accent_color = RANDOM_ACCENT_COLORS.sample
  end

  def accent_color_contrast(color)
    raise 'no brand color' unless accent_color

    WCAGColorContrast.ratio(accent_color.gsub('#', ''), color.gsub('#', ''))
  end

  def register_lists
    subscribe(WelcomeMailer::LIST)
    subscribe(AccountMailer::ANALYTICS_SUMMARY_LIST)
  end

  def register_welcome_emails
    #    WelcomeMailer.greet_new_account(self).deliver_later(wait: 15.minutes)
    # WelcomeMailer.how_i_replaced_twitter(self).deliver_later(wait: 1.day)
    # WelcomeMailer.getting_most_out_of_postcard(self).deliver_later(wait: 2.days)
    # WelcomeMailer.social_networks_over(self).deliver_later(wait: 3.days)
    # WelcomeMailer.why_have_personal_website(self).deliver_later(wait: 5.days)
    # WelcomeMailer.cool_uses_for_personal_website(self).deliver_later(wait: 7.days)
  end
end
