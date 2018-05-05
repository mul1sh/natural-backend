class SyncDbJob < ApplicationJob
  queue_as :default

  def sync_db
    db_manager = ::Natural::DatabaseManager.new
    Table.all.each do |table|
      # TODO: remove next line, after root issue is fixed (Table validation to ensure name won't be blank and data cleaning, i.e. tables with blank name)
      next if table.name.blank?

      db_manager.connect_to_database(table.database.database_identifier)

      to_be_removed_ids = table.rows.pluck(:db_id)

      query = <<-SQL
        SELECT *
        FROM \"#{table.name}\"
      SQL

      db_manager.connection.exec(query).each do |row|
        row_db_id = row.values_at('id')[0].to_i

        to_be_removed_ids.delete(row_db_id)

        if app_layer_row = Row.find_by(db_id: row_db_id)
          # TODO: implement updating from service layer database to app layer database
          # table.columns.each do |column|
          #   value = row.values_at(column.name)[0]
          #   row_value = RowValue.find_or_create_by(row: app_layer_row, column: column, user: table.user)
          #   row_value.update_attribute(:value, value)
          # end
        else
          app_layer_row = Row.create(db_id: row.values_at('id')[0], table: table, user: table.user)
          table.columns.each do |column|
            value = row.values_at(column.name)[0]
            RowValue.create(row: app_layer_row, column: column, value: value, user: table.user)
          end
        end

      end

      Row.where(db_id: to_be_removed_ids).destroy_all
    end
  end

  def perform
    RedisMutex.with_lock(:sync_db) do
      ActiveRecord::Base.logger.silence do
        sync_db
      end
    rescue RedisMutex::LockError
      Rails.logger.debug "Another job is running, exiting ..."
    end
  end
end
