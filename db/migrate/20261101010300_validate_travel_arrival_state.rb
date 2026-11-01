class ValidateTravelArrivalState < ActiveRecord::Migration[8.0]
  def up
    execute "SET LOCAL lock_timeout = '2s'"
    validate_check_constraint :ship_travels,name:'ship_travels_arrival_state'
  end
  def down
    # Keep the checked condition on rollback; no player data is rewritten.
  end
end
