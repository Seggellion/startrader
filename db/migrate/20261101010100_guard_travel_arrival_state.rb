class GuardTravelArrivalState < ActiveRecord::Migration[8.0]
  CONDITION = <<~SQL.squish.freeze
    arrival_tick IS NOT NULL AND arrival_tick >= 0 AND
    (arrival_tick > 0 OR
      (is_paused IS TRUE AND completed_at_tick IS NULL AND
       departure_tick IS NOT NULL AND departure_tick >= 0 AND
       paused_at_tick IS NOT NULL AND paused_at_tick >= departure_tick AND
       remaining_ticks_from_arrival IS NOT NULL AND remaining_ticks_from_arrival >= 0 AND
       interdiction_count IS NOT NULL AND interdiction_count > 0 AND
       last_interdicted_tick IS NOT NULL AND last_interdicted_tick = paused_at_tick))
  SQL
  def up
    execute "SET LOCAL lock_timeout = '2s'"
    add_check_constraint :ship_travels, CONDITION, name:'ship_travels_arrival_state',validate:false
  end
  def down
    remove_check_constraint :ship_travels,name:'ship_travels_arrival_state'
  end
end
