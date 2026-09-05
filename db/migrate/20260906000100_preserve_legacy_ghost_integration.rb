# frozen_string_literal: true

class PreserveLegacyGhostIntegration < ActiveRecord::Migration[7.1]
  def up
    # Preserve the account that the old controller enabled. Keep this identity
    # in the one-time upgrade, rather than in ongoing subscription processing.
    execute "UPDATE accounts SET sync_to_ghost = TRUE WHERE slug = 'philipithomas'"
  end

  def down
    # Do not overwrite an operator's preference when rolling back the backfill.
    # Rolling back AddSyncToGhostToAccounts removes the setting itself.
  end
end
