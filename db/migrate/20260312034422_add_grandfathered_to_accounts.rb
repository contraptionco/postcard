# frozen_string_literal: true

class AddGrandfatheredToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :grandfathered, :boolean, default: false, null: false
    Account.update_all(grandfathered: true)
  end

  def down
    remove_column :accounts, :grandfathered
  end
end
