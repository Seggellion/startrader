class CreateTravelResumeActions < ActiveRecord::Migration[8.0]
  def up
    create_table :travel_resume_actions do |t|
      t.string :travel_guid, null: false
      t.bigint :ship_travel_id, null: false
      t.bigint :user_ship_id, null: false
      t.integer :interdiction_count, null: false
      t.integer :last_interdicted_tick, null: false
      t.string :actor_kind, null: false
      t.references :admin_user, foreign_key: {to_table: :users, on_delete: :nullify}
      t.string :actor_label, null: false
      t.text :reason, null: false
      t.integer :resumed_at_tick, null: false
      t.integer :remaining_ticks, null: false
      t.integer :arrival_tick, null: false
      t.string :rabbitmq_environment, null: false
      t.jsonb :before_state, null: false
      t.jsonb :after_state, null: false
      t.timestamps
    end
    add_index :travel_resume_actions, [:travel_guid, :interdiction_count],
      unique: true, name: 'index_one_resume_action_per_interdiction'
    add_index :travel_resume_actions, :ship_travel_id
    add_index :travel_resume_actions, :user_ship_id
  end

  def down
    if table_exists?(:travel_resume_actions) && select_value('SELECT 1 FROM travel_resume_actions LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Retain durable resume audit records; code rollback does not drop this table.'
    end
    drop_table :travel_resume_actions
  end
end
