# frozen_string_literal: true

require 'test_helper'

class AdminAccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = accounts(:grandfathered_user)
    @admin.update_columns(admin: true)
    @author = accounts(:new_user)
    @author.update_columns(grandfathered: true)
    host! Rails.configuration.base_host
  end

  if Rails.configuration.multiuser_mode
    test 'guests cannot look up private account details' do
      post admin_accounts_search_path, params: { account_email: @author.email }

      assert_response :redirect
      assert_equal new_account_session_path, URI(response.location).path
      assert_not_includes response.body, @author.email
    end

    test 'signed in authors cannot search other accounts' do
      sign_in @author
      post admin_accounts_search_path, params: { account_email: @admin.email }

      assert_response :forbidden
      assert_not_includes response.body, @admin.email
    end

    test 'admin lookup normalizes whitespace and case while keeping navigation on the admin account' do
      sign_in @admin
      post admin_accounts_search_path, params: { account_email: "  #{@author.email.upcase} \n" }

      assert_response :success
      assert_select 'input[name=account_email]', value: @author.email
      assert_select 'section[aria-label="Account details"]' do
        assert_select 'h2', text: @author.name
        assert_select 'p', text: @author.email
        assert_select "a[href='#{page_path(@author)}']", text: 'View dashboard'
        assert_select "a[href='#{@author.url}'][rel=noopener]", text: 'View public page'
      end
      assert_select "a[href='#{page_posts_path(@admin)}']", minimum: 1
      assert_select "a[href='#{admin_accounts_search_path}']", minimum: 1
    end

    test 'search keeps email out of URLs analytics and logged parameters' do
      sign_in @admin
      assert_no_difference 'Ahoy::Event.count' do
        get admin_accounts_search_path

        assert_response :success
        assert_select 'form[method=post][data-turbo=false]' do
          assert_select 'input[name=account_email][type=email]'
        end

        post admin_accounts_search_path, params: { account_email: @author.email }

        assert_response :success
        assert_equal '', request.query_string
        assert_not_includes request.original_url, @author.email
        assert_equal '[FILTERED]', request.filtered_parameters['account_email']
        assert_select 'section[aria-label="Account details"] p', text: @author.email
      end
    end

    test 'subscriber total counts only confirmed subscriptions that are still active' do
      [
        { verified_at: Time.current },
        { verified_at: nil },
        { verified_at: Time.current, unsubscribed_at: Time.current }
      ].each_with_index do |state, index|
        email = EmailAddress.create!(email: "admin-count-#{index}@example.com")
        @author.subscriptions.create!({ email_address: email, source: :signup }.merge(state))
      end
      sign_in @admin
      post admin_accounts_search_path, params: { account_email: @author.email }

      assert_response :success
      assert_select 'dl div', text: /Subscribers/ do
        assert_select 'dd', text: '1'
      end
    end

    test 'blank searches do not display an account or a not-found message' do
      sign_in @admin
      post admin_accounts_search_path, params: { account_email: '  ' }

      assert_response :success
      assert_select 'section[aria-label="Account details"]', count: 0
      assert_select 'p[role=status]', count: 0
    end

    test 'unknown and partial addresses have a normal empty result' do
      sign_in @admin
      ['missing@example.com', @author.email.split('@').first].each do |query|
        post admin_accounts_search_path, params: { account_email: query }

        assert_response :success
        assert_select 'section[aria-label="Account details"]', count: 0
        assert_select 'p[role=status]', text: "No account found for #{query}."
        assert_not_includes response.body, @author.email
      end
    end

    test 'profile photos have descriptive alternative text' do
      @author.photo.attach(io: StringIO.new(Vips::Image.black(8, 8).write_to_buffer('.png')),
                           filename: 'profile.png', content_type: 'image/png')
      sign_in @admin
      post admin_accounts_search_path, params: { account_email: @author.email }

      assert_response :success
      assert_select 'section[aria-label="Account details"] img', alt: "#{@author.name}'s profile photo"
    ensure
      @author.photo.purge if @author.photo.attached?
    end

    test 'the search menu follows the signed-in administrator when viewing another author' do
      sign_in @admin
      get page_path(@author)

      assert_response :success
      assert_select "a[href='#{admin_accounts_search_path}']", minimum: 1
      assert_select 'a[href="/jobs"]', minimum: 1

      sign_out @admin
      sign_in @author
      get page_path(@author)

      assert_response :success
      assert_select "a[href='#{admin_accounts_search_path}']", count: 0
      assert_select 'a[href="/jobs"]', count: 0
    end

    test 'account search is unavailable on an author subdomain' do
      sign_in @admin
      host! "#{@author.slug}.#{Rails.configuration.base_host}"

      assert_raises(ActionController::RoutingError) do
        post '/admin/accounts/search', params: { account_email: @author.email }
      end
    end
  else
    test 'solo mode does not expose the search route to guests or administrators' do
      assert_raises(ActionController::RoutingError) { get '/admin/accounts/search' }
      assert_raises(ActionController::RoutingError) { post '/admin/accounts/search' }
      sign_in @admin
      assert_raises(ActionController::RoutingError) { get '/admin/accounts/search' }
      assert_raises(ActionController::RoutingError) { post '/admin/accounts/search' }
    end

    test 'solo dashboard renders without an account-search menu' do
      sign_in @admin
      get page_path(@admin)

      assert_response :success
      assert_select 'a[href="/admin/accounts/search"]', count: 0
    end
  end
end
