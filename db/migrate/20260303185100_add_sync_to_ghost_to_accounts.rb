# frozen_string_literal: true

class AddSyncToGhostToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :sync_to_ghost, :boolean, default: false, null: false
  end
end
