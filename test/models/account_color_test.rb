# frozen_string_literal: true

require 'test_helper'

class AccountColorTest < ActiveSupport::TestCase
  test 'theme colors accept six hex digits and render RGB' do
    account = accounts(:new_user)
    %w[#ff0000 #ABCDEF #012345].each do |color|
      account.accent_color = color
      assert account.valid?, account.errors.full_messages.join(', ')
    end
    assert_equal 'rgb(1, 35, 69)', account.accent_color_rgb
  end

  test 'theme colors reject CSS and markup injection' do
    account = accounts(:new_user)
    ['red', '#abc', "#123456\n", 'red; } body { display:none }', '</style><script>alert(1)</script>'].each do |color|
      account.accent_color = color
      refute account.valid?
      assert account.errors[:accent_color].present?
    end
  end

  test 'uninitialized theme color has no RGB value' do
    assert_nil Account.new.accent_color_rgb
  end
end
