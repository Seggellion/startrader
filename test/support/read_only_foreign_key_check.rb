# Rails 8.0.1 revalidates fixtures by updating pg_catalog.pg_constraint, which
# requires a superuser. Keep real validation without granting that privilege:
# inspect each FK's rows using ordinary SELECTs. PostgreSQL's constraints also
# remain enabled under the limited test role.
require 'active_record/connection_adapters/postgresql_adapter'

module ReadOnlyForeignKeyCheck
  def check_all_foreign_keys_valid!
    tables.each do |table|
      foreign_keys(table).each do |fk|
        columns = Array(fk.column)
        keys = Array(fk.primary_key)
        required = columns.map { |column| "c.#{quote_column_name(column)} IS NOT NULL" }.join(' AND ')
        match = columns.zip(keys).map do |column, key|
          "p.#{quote_column_name(key)} = c.#{quote_column_name(column)}"
        end.join(' AND ')
        invalid = select_value(<<~SQL)
          SELECT 1 FROM #{quote_table_name(table)} c
          WHERE #{required} AND NOT EXISTS (
            SELECT 1 FROM #{quote_table_name(fk.to_table)} p WHERE #{match}
          ) LIMIT 1
        SQL
        raise ActiveRecord::InvalidForeignKey, "Invalid fixture foreign key #{fk.name}" if invalid
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(ReadOnlyForeignKeyCheck)
