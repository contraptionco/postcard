# frozen_string_literal: true

require 'test_helper'

class GroverRuntimeTest < ActiveSupport::TestCase
  test 'Ruby renders an Open Graph image using the locked Node browser' do
    png = Grover.new('<!doctype html><html><body><h1>Postcard</h1></body></html>').to_png

    assert_equal "\x89PNG\r\n\x1a\n".b, png.byteslice(0, 8)
    assert_equal [1128, 600], png.byteslice(16, 8).unpack('NN')
  end
end
