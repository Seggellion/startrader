class CreateTravelLifecycleReceipts < ActiveRecord::Migration[8.0]
  def change
    # Durable history intentionally survives deletion of journeys/ships.
    create_table :travel_request_receipts do |t|
      t.string :travel_guid, null:false
      t.bigint :user_ship_id, null:false
      t.jsonb :request_context, null:false, default:{}
      t.jsonb :travel_snapshot, null:false, default:{}
      t.string :outcome, null:false, default:'pending'
      t.integer :completed_at_tick
      t.timestamps
    end
    add_index :travel_request_receipts, :travel_guid, unique:true
    add_index :travel_request_receipts, :user_ship_id
    create_table :travel_arrival_events do |t|
      t.string :event_guid, null:false
      t.string :travel_guid, null:false
      t.string :rabbitmq_environment, null:false
      t.jsonb :payload, null:false
      t.integer :attempts, null:false, default:0
      t.datetime :next_attempt_at
      t.datetime :sent_at
      t.string :last_error_class
      t.timestamps
    end
    add_index :travel_arrival_events, :event_guid, unique:true
    add_index :travel_arrival_events, :travel_guid, unique:true
    add_index :travel_arrival_events, [:next_attempt_at,:id], where:'sent_at IS NULL', name:'index_pending_travel_arrivals'
  end
end
