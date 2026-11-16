namespace :status_location do
  desc "Read-only location integrity audit (aggregate counts only, no identifiers)"
  task audit: :environment do
    report = nil
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
      report = StatusLocationAudit.new.report
      report[:transaction_read_only] = ActiveRecord::Base.connection.select_value("SHOW transaction_read_only")
      raise ActiveRecord::Rollback
    end
    puts JSON.pretty_generate(report)
  end
end
