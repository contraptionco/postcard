# frozen_string_literal: true

domain_redirects = {
  "www.postcard.page" => "postcard.page"
}.freeze


Rails.application.routes.draw do
  domain_redirects.each do |source, target|
    constraints(host: source) do
      root to: redirect("https://#{target}"), as: "redirect_#{source.tr(".", "_")}"
      match "*path", via: :all, to: redirect { |params, request|
        "https://#{target}#{request.fullpath}"
      }
    end
  end


  #
  # Application routes
  #
  mount Pay::Engine, at: '/pay', :constraints => { :host => Rails.configuration.base_host }

  authenticate :account, ->(account) { account.admin? } do
    mount Blazer::Engine, at: 'analytics'
    mount MissionControl::Jobs::Engine, at: "/jobs", :constraints => { :host => Rails.configuration.base_host }
    mount PgHero::Engine, at: 'db', :constraints => { :host => Rails.configuration.base_host }
  end

  namespace :admin, :constraints => { :host => Rails.configuration.base_host } do
    get 'accounts/search', to: 'accounts#search', as: :accounts_search
  end

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: '/letter_opener', :constraints => { :host => Rails.configuration.base_host }
  end

  devise_scope :account do
    get 'accounts', to: 'devise/sessions#new', :constraints => { :host => Rails.configuration.base_host }
  end

  devise_for :accounts, :constraints => { :host => Rails.configuration.base_host }, controllers: {
    passwords: 'accounts/passwords',
    registrations: 'accounts/registrations',
    confirmations: 'accounts/confirmations',
    omniauth_callbacks: 'accounts/omniauth_callbacks',
    sessions: 'accounts/sessions'
  }

  get '/' => 'marketing_pages#homepage', :constraints => { :host => Rails.configuration.base_host }
  get '/alternative/:slug' => 'marketing_pages#alternative', :constraints => { :host => Rails.configuration.base_host }
  get '/discover' => redirect('/'), :constraints => { :host => Rails.configuration.base_host }
  get 'sitemap.xml', to: 'marketing_pages#sitemap', format: 'xml', as: :marketing_sitemap,
                     :constraints => { :host => Rails.configuration.base_host }

  resources :feedbacks, :constraints => { :host => Rails.configuration.base_host } unless Rails.configuration.solo_mode
  resources :activation, param: :token, path: 'activate', :constraints => { :host => Rails.configuration.base_host }

  resources :pages, param: :slug, :constraints => { :host => Rails.configuration.base_host } do
    resources :setup
    get 'subscribers/export', to: 'subscribers#export'
    resources :subscribers_imports, path: 'subscribers/import'
    resources :subscribers
    resources :showcase unless Rails.configuration.solo_mode
    resources :posts, param: :slug do
      resources :draft
    end
    put 'account', to: 'account#update'
    get 'checkout', to: 'checkout#show', as: :checkout
    get 'billing', to: 'billing#show', as: :billing
  end

  # Global
  get '/robots.:format' => 'robots#show'
  get '/.postcard', to: proc { [200, {}, ['postcard']] }

  resources :unsubscription, path: 'unsubscribe', param: :token

  #
  # Public - wildcard route
  #
  root 'public_pages#show'
  get '/og/:updated_at', to: 'public_pages#og_image', as: :public_page_og_image
  post '/' => 'public_pages#create'
  resources :subscription_verifications, only: %i[show]
  resources :public_posts, path: 'posts', param: :slug
  get '/posts/:slug/og/:updated_at', to: 'public_posts#og_image', as: :public_post_og_image
  get 'sitemap.xml', to: 'public_pages#sitemap', format: 'xml', as: :public_page_sitemap

  #
  # CDN
  #
  direct :cdn_proxy do |model, options|
    expires_in = options.delete(:expires_in) { ActiveStorage.urls_expire_in }

    # In solo mode, use regular Rails Active Storage routes
    # In multiuser mode, use CDN proxy routes with CDN host
    if Rails.configuration.solo_mode
      # Use regular Rails Active Storage routes for solo mode
      if model.respond_to?(:signed_id)
        route_for(
          :rails_service_blob_proxy,
          model.signed_id(expires_in: expires_in),
          model.filename,
          options
        )
      else
        signed_blob_id = model.blob.signed_id(expires_in: expires_in)
        variation_key  = model.variation.key
        filename       = model.blob.filename

        route_for(
          :rails_blob_representation_proxy,
          signed_blob_id,
          variation_key,
          filename,
          options
        )
      end
    else
      # Use CDN proxy routes for multiuser mode
      if model.respond_to?(:signed_id)
        route_for(
          :rails_service_blob_proxy,
          model.signed_id(expires_in: expires_in),
          model.filename,
          options.merge(host: Rails.configuration.cdn_host)
        )
      else
        signed_blob_id = model.blob.signed_id(expires_in: expires_in)
        variation_key  = model.variation.key
        filename       = model.blob.filename

        route_for(
          :rails_blob_representation_proxy,
          signed_blob_id,
          variation_key,
          filename,
          options.merge(host: Rails.configuration.cdn_host)
        )
      end
    end
  end
end
