class AddRabbitmqEnvironmentToShipTravels < ActiveRecord::Migration[8.0]
  DEFAULT_ENVIRONMENT = "prod".freeze

  def up
    unless column_exists?(:ship_travels, :rabbitmq_environment)
      # Existing rows and existing API callers keep production behaviour: the
      # column default backfills every in-flight travel to "prod".
      add_column :ship_travels, :rabbitmq_environment, :string,
        null: false, default: DEFAULT_ENVIRONMENT
    end

    execute <<~SQL.squish
      UPDATE ship_travels
      SET rabbitmq_environment = '#{DEFAULT_ENVIRONMENT}'
      WHERE rabbitmq_environment IS NULL OR TRIM(rabbitmq_environment) = ''
    SQL
  end

  def down
    remove_column :ship_travels, :rabbitmq_environment if column_exists?(:ship_travels, :rabbitmq_environment)
  end
end
