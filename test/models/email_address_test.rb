# frozen_string_literal: true

require 'test_helper'

class EmailAddressTest < ActiveSupport::TestCase
  test 'rejects one-character suffixes without persisting an address' do
    %w[reader@example.c reader@news.example.Z].each do |email|
      address = EmailAddress.new(email: email)

      assert_no_difference('EmailAddress.count') { assert_not address.save }
      assert_includes address.errors[:email], 'is invalid'
    end
  end

  test 'accepts existing address forms and longer suffixes' do
    %w[reader@example.co first.last@example.com reader+letters@example.photography
       first_last@news.example.org reader-name@example.travel reader@xn--bcher-kva.de].each do |email|
      address = EmailAddress.create!(email: email)

      assert_equal email, address.reload.email
    end
  end

  test 'normalizes case when saving without removing plus addressing' do
    address = EmailAddress.create!(email: 'Reader+Letters@EXAMPLE.MUSEUM')

    assert_equal 'reader+letters@example.museum', address.reload.email
  end

  test 'rejects missing or malformed addresses' do
    [nil, '', 'reader@example', 'reader@@example.com', 'reader@example.12',
     'reader name@example.com', ' reader@example.com ', 'reader@example..com',
     'reader@-example.com', 'reader@example-.com', 'reader@.example.com',
     "reader@#{'a' * 64}.com", "reader@example.#{'a' * 64}"].each do |email|
      address = EmailAddress.new(email: email)

      assert_not address.valid?, "Expected #{email.inspect} to be rejected"
      assert address.errors[:email].any?
    end
  end

  test 'keeps the existing 255-character address limit' do
    accepted = EmailAddress.new(email: "#{'a' * 243}@example.com")
    rejected = EmailAddress.new(email: "#{'a' * 244}@example.com")

    assert accepted.valid?
    assert_not rejected.valid?
    assert_includes rejected.errors[:email], 'is too long (maximum is 255 characters)'
  end

  test 'imports normalize and filter addresses using the same suffix policy' do
    import = SubscribersImport.new(account: accounts(:new_user), sources_description: 'Reader opt-ins')
    import.file.attach(io: StringIO.new("email\n Reader+Letters@EXAMPLE.MUSEUM \nreader@example.c\nreader@example..com\nreader@-example.com\nreader@example-.com\nreader@example.co\nreader@example.co\n"),
                       filename: 'readers.csv', content_type: 'text/csv')
    import.save!

    assert_equal %w[reader+letters@example.museum reader@example.co], import.emails
    assert_equal 2, import.emails_count
    assert import.emails.all? { |email| EmailAddress.new(email: email).valid? }
  end
end
