# frozen_string_literal: true

class AddWabiSabiMode < ActiveRecord::Migration[7.1]
  def change
    # Add wabi_sabi_mode setting to accounts
    add_column :accounts, :wabi_sabi_mode, :boolean, default: false, null: false

    # Add columns to posts to store the photo and cover blob IDs at publish time
    # These reference the blob that was attached when the post was published
    add_reference :posts, :published_photo_blob, foreign_key: { to_table: :active_storage_blobs }
    add_reference :posts, :published_cover_blob, foreign_key: { to_table: :active_storage_blobs }
  end
end
