# frozen_string_literal: true

require 'test_helper'

class AccountTest < ActiveSupport::TestCase
  setup do
    @original_solo_mode = Rails.configuration.solo_mode
    @original_multiuser_mode = Rails.configuration.multiuser_mode
  end

  teardown do
    Rails.configuration.solo_mode = @original_solo_mode
    Rails.configuration.multiuser_mode = @original_multiuser_mode
  end

  test "active_subscription? returns true in solo mode" do
    Rails.configuration.solo_mode = true
    account = accounts(:new_user)
    assert account.active_subscription?
  end

  test "active_subscription? returns false for non-subscribed multiuser account" do
    Rails.configuration.solo_mode = false
    account = accounts(:new_user)
    refute account.active_subscription?
  end

  test "requires_payment? returns false in solo mode" do
    Rails.configuration.solo_mode = true
    account = accounts(:new_user)
    refute account.requires_payment?
  end

  test "requires_payment? returns false for grandfathered accounts" do
    Rails.configuration.solo_mode = false
    account = accounts(:grandfathered_user)
    refute account.requires_payment?
  end

  test "requires_payment? returns true for new non-grandfathered non-subscribed accounts" do
    Rails.configuration.solo_mode = false
    account = accounts(:new_user)
    assert account.requires_payment?
  end

  test "ever_subscribed? returns false for fresh accounts" do
    account = accounts(:new_user)
    refute account.ever_subscribed?
  end
end
