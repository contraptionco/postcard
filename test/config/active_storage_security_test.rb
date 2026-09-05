# frozen_string_literal: true

require 'test_helper'

class ActiveStorageSecurityTest < ActiveSupport::TestCase
  test 'application boot blocks unfuzzed libvips loaders' do
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2"/></svg>'

    # An absent loader must not make this security check pass.
    assert_operator Vips.type_find('VipsOperation', 'svgload_buffer'), :>, 0
    error = assert_raises(Vips::Error) { Vips::Image.svgload_buffer(svg) }
    assert_match(/operation is blocked/, error.message)
  end

  %w[png jpeg].each do |format|
    test "processes #{format} uploads into resized WebP variants" do
      image = Vips::Image.black(32, 16, bands: 3).copy(interpretation: :srgb)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(image.write_to_buffer(".#{format}")),
        filename: "photo.#{format}",
        content_type: "image/#{format}"
      )

      variant = blob.variant(resize_to_fill: [8, 8, { crop: :attention }], format: :webp).processed
      resized = Vips::Image.new_from_buffer(variant.download, '')

      assert_equal 'image/webp', variant.content_type
      assert_equal [8, 8], [resized.width, resized.height]
    ensure
      variant.image.purge if variant.respond_to?(:image)
      variant&.destroy
      blob&.purge
    end
  end
end
