class AddCascadeDeleteToStarBitizenRunsUserForeignKey < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :star_bitizen_runs, :users
    add_foreign_key :star_bitizen_runs, :users, on_delete: :cascade
  end

  def down
    remove_foreign_key :star_bitizen_runs, :users
    add_foreign_key :star_bitizen_runs, :users
  end
end
