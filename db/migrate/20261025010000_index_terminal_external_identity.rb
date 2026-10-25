class IndexTerminalExternalIdentity < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  NAME = "index_terminals_on_unique_api_id"

  def up
    duplicate = select_value("SELECT api_id FROM terminals WHERE api_id IS NOT NULL GROUP BY api_id HAVING COUNT(*) > 1 LIMIT 1")
    raise ActiveRecord::MigrationError, "Duplicate terminal api_id; audit before creating the unique index" if duplicate
    add_index :terminals, :api_id, unique: true, where: "api_id IS NOT NULL", name: NAME, algorithm: :concurrently
  end

  def down
    remove_index :terminals, name: NAME, algorithm: :concurrently
  end
end
