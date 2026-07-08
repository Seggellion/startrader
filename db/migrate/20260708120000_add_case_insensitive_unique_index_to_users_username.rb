class AddCaseInsensitiveUniqueIndexToUsersUsername < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :users,
      "LOWER(username)",
      unique: true,
      name: "index_users_on_lower_username_unique",
      where: "username IS NOT NULL AND username <> ''",
      algorithm: :concurrently
  end
end
