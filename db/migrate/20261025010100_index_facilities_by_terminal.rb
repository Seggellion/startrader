class IndexFacilitiesByTerminal < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_index :production_facilities, :id_terminal, algorithm: :concurrently
  end

  def down
    remove_index :production_facilities, :id_terminal, algorithm: :concurrently
  end
end
