# frozen_string_literal: true

require 'test_helper'

class AccountTest < ActiveSupport::TestCase
  test 'should accept valid hex color for accent_color' do
    account = Account.new(
      email: 'test@example.com',
      password: 'password123',
      name: 'Test User',
      slug: 'test-user',
      accent_color: '#ff0000'
    )
    assert account.valid?
  end

  test 'should reject accent_color with CSS injection attempt' do
    account = Account.new(
      email: 'test2@example.com',
      password: 'password123',
      name: 'Test User 2',
      slug: 'test-user-2',
      accent_color: 'red; } body { display:none } .x {'
    )
    assert_not account.valid?
    assert account.errors[:accent_color].present?
  end

  test 'should reject accent_color with closing style tag' do
    account = Account.new(
      email: 'test3@example.com',
      password: 'password123',
      name: 'Test User 3',
      slug: 'test-user-3',
      accent_color: '</style><script>alert("XSS")</script>'
    )
    assert_not account.valid?
    assert account.errors[:accent_color].present?
  end

  test 'should reject invalid hex colors' do
    invalid_colors = [
      'red',           # Named color
      '#ff00',         # Too short
      '#ff00000',      # Too long
      '#gggggg',       # Invalid hex characters
      'rgb(255,0,0)',  # RGB format
      '#ff00;',        # Hex with semicolon
      '000000',        # Missing #
    ]

    invalid_colors.each do |color|
      account = Account.new(
        email: "test-#{color.gsub(/[^a-z0-9]/, '')}@example.com",
        password: 'password123',
        name: 'Test User',
        slug: "test-user-#{color.gsub(/[^a-z0-9]/, '')}",
        accent_color: color
      )
      assert_not account.valid?, "#{color} should be invalid"
      assert account.errors[:accent_color].present?, "#{color} should have accent_color error"
    end
  end

  test 'should accept valid hex colors with lowercase' do
    account = Account.new(
      email: 'test4@example.com',
      password: 'password123',
      name: 'Test User 4',
      slug: 'test-user-4',
      accent_color: '#abc123'
    )
    assert account.valid?
  end

  test 'should accept valid hex colors with uppercase' do
    account = Account.new(
      email: 'test5@example.com',
      password: 'password123',
      name: 'Test User 5',
      slug: 'test-user-5',
      accent_color: '#ABC123'
    )
    assert account.valid?
  end

  test 'should allow nil accent_color and set random color on save' do
    account = Account.new(
      email: 'test6@example.com',
      password: 'password123',
      name: 'Test User 6',
      slug: 'test-user-6',
      accent_color: nil
    )
    # The validation allows nil
    assert account.valid?
    # But the set_random_accent_color callback should set a color on save
    # (We don't save here to avoid database interactions in this unit test)
  end

  test 'accent_color_rgb returns nil when accent_color is nil' do
    account = Account.new
    account.accent_color = nil
    assert_nil account.accent_color_rgb
  end

  test 'accent_color_rgb converts valid hex to rgb' do
    account = Account.new
    account.accent_color = '#ff0000'
    assert_equal 'rgb(255, 0, 0)', account.accent_color_rgb
  end
end
