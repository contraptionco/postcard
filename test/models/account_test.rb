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

  %w[png jpg].each do |extension|
    test "generate_icon creates a circular PNG from a #{extension} photo" do
      account = accounts(:new_user)
      attach_photo(account, extension)

      account.generate_icon

      assert account.icon.attached?
      assert_equal 'image/png', account.icon.content_type
      image = Vips::Image.new_from_buffer(account.icon.download, '')
      assert_equal [800, 800, 4], [image.width, image.height, image.bands]
      [[0, 0], [799, 0], [0, 799], [799, 799]].each do |x, y|
        assert_equal 0, image.getpoint(x, y).last
      end
      assert_equal 255, image.getpoint(400, 400).last
      [40, 80, 120].zip(image.getpoint(400, 400).first(3)).each do |expected, actual|
        assert_in_delta expected, actual, 2
      end
    end
  end

  test 'generate_icon purges the icon when the photo is removed' do
    account = accounts(:new_user)
    attach_photo(account, 'png')
    account.generate_icon
    icon_blob_id = account.icon.blob.id
    account.photo.purge

    account.generate_icon

    refute account.icon.attached?
    refute ActiveStorage::Blob.exists?(icon_blob_id)
  end

  private

  def attach_photo(account, extension)
    image = (Vips::Image.black(1000, 600, bands: 3) + [40, 80, 120]).copy(interpretation: :srgb)
    account.photo.attach(io: StringIO.new(image.write_to_buffer(".#{extension}")),
                         filename: "photo.#{extension}",
                         content_type: extension == 'jpg' ? 'image/jpeg' : 'image/png')
  end
end
