# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class UpdatesAccountDeletionTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:new_user)
    @updates = accounts(:grandfathered_user)
    @updates.update_columns(slug: 'updates')
  end

  test 'deletion removes updates memberships and mail from recorded former and current addresses' do
    old_membership, old_message = updates_mail(@account.email)
    @account.update!(email: 'middle-address@example.com')
    middle_membership, middle_message = updates_mail(@account.email)
    @account.update!(email: 'current-address@example.com')
    current_membership, current_message = updates_mail(@account.email)
    unrelated_membership, unrelated_message = updates_mail('unrelated-reader@example.com')
    other_author = create_account('other-author@example.com')
    other_message = EmailMessage.create!(account: other_author, user: old_membership.email_address,
                                        to: old_membership.email_address.email)
    recipient_ids = [old_membership, middle_membership, current_membership].map(&:email_address_id)

    DestroyAccountJob.perform_now(@account)

    [old_membership, middle_membership, current_membership].each { |membership| refute Subscription.exists?(membership.id) }
    [old_message, middle_message, current_message].each { |message| refute EmailMessage.exists?(message.id) }
    assert Subscription.exists?(unrelated_membership.id)
    assert EmailMessage.exists?(unrelated_message.id)
    assert EmailMessage.exists?(other_message.id), 'another author owns its own recipient history'
    assert_equal 3, EmailAddress.where(id: recipient_ids).count
    refute Audited::Audit.where(auditable_type: 'Account', auditable_id: @account.id).exists?
  end

  test 'deletion preserves a former address now used by another account' do
    previous_email = @account.email
    membership, message = updates_mail(previous_email)
    @account.update!(email: 'changed-owner@example.com')
    new_owner = create_account(previous_email)

    DestroyAccountJob.perform_now(@account)

    assert Account.exists?(new_owner.id)
    assert Subscription.exists?(membership.id)
    assert EmailMessage.exists?(message.id)
  end

  test 'deletion preserves a former address reverified later by a reader without an account' do
    membership, message = updates_mail(@account.email)
    @account.update!(email: 'changed-reader@example.com')
    travel 1.minute do
      membership.update!(verified_at: Time.current)
      DestroyAccountJob.perform_now(@account)
    end

    assert Subscription.exists?(membership.id)
    assert EmailMessage.exists?(message.id)
  end

  test 'deletion preserves a later signup at a former address' do
    previous_email = @account.email
    @account.update!(email: 'changed-signup@example.com')
    membership = message = nil
    travel 1.minute do
      membership, message = updates_mail(previous_email)
      DestroyAccountJob.perform_now(@account)
    end

    assert Subscription.exists?(membership.id)
    assert EmailMessage.exists?(message.id)
  end

  private

  def updates_mail(email)
    recipient = EmailAddress.find_or_create_by!(email: email)
    membership = @updates.subscriptions.create!(email_address: recipient, source: :signup, verified_at: Time.current)
    message = EmailMessage.create!(account: @updates, user: recipient, subscription: membership, to: email)
    [membership, message]
  end

  def create_account(email)
    Truemail.stub(:valid?, true) { Account.create!(name: 'Another Author', email: email, password: 'password123') }
  end
end
