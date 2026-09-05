# frozen_string_literal: true

require 'test_helper'
require Rails.root.join('db/migrate/20260906000100_preserve_legacy_ghost_integration')

class GhostIntegrationUpgradeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test 'new accounts and existing ordinary authors default to opted out' do
    refute Account.new.sync_to_ghost?
    refute accounts(:new_user).sync_to_ghost?
    refute accounts(:grandfathered_user).sync_to_ghost?
  end

  test 'upgrade preserves the legacy integration without opting in other authors or exporting subscribers' do
    legacy = accounts(:grandfathered_user)
    legacy.update!(slug: 'philipithomas')

    assert_no_enqueued_jobs do
      PreserveLegacyGhostIntegration.new.up
    end
    assert legacy.reload.sync_to_ghost?
    refute accounts(:new_user).reload.sync_to_ghost?
  end

  test 'backfill rollback preserves explicit settings made after the upgrade' do
    account = accounts(:new_user)
    account.update!(sync_to_ghost: true)
    PreserveLegacyGhostIntegration.new.down
    assert account.reload.sync_to_ghost?
  end
end
