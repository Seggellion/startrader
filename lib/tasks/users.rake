# lib/tasks/users.rake

namespace :users do
  desc "Remove duplicate users by case-insensitive username"
  task dedupe_usernames: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"

    # Use this to limit the task to recently-created accounts only.
    # Example:
    # CREATED_AFTER=2026-07-01 rails users:dedupe_usernames
    created_after = ENV["CREATED_AFTER"]&.then { |value| Time.zone.parse(value) }

    unless created_after
      abort "Please provide CREATED_AFTER=YYYY-MM-DD to avoid deleting older established accounts."
    end

    normalized_usernames = User
      .where.not(username: [nil, ""])
      .group("LOWER(username)")
      .having("COUNT(*) > 1")
      .pluck(Arel.sql("LOWER(username)"))

    puts "Found #{normalized_usernames.size} duplicated username group(s)."
    puts "DRY_RUN=#{dry_run}"
    puts "CREATED_AFTER=#{created_after}"

    destroyed_count = 0
    skipped_count = 0

    normalized_usernames.each do |normalized_username|
      users = User
        .where("LOWER(username) = ?", normalized_username)
        .order(created_at: :desc, id: :desc)
        .to_a

      keeper = users.first
      candidates = users.drop(1)

      puts "\nDuplicate username: #{normalized_username}"
      puts "Keeping newest user ##{keeper.id} username=#{keeper.username.inspect} created_at=#{keeper.created_at}"

      candidates.each do |user|
        unless user.created_at >= created_after
          skipped_count += 1
          puts "Skipping older established user ##{user.id} username=#{user.username.inspect} created_at=#{user.created_at}"
          next
        end

        puts "Destroying duplicate user ##{user.id} username=#{user.username.inspect} created_at=#{user.created_at}"

        unless dry_run
          user.destroy!
        end

        destroyed_count += 1
      end
    end

    puts "\nDone."
    puts "Destroyed: #{dry_run ? 0 : destroyed_count}"
    puts "Would destroy: #{dry_run ? destroyed_count : 0}"
    puts "Skipped: #{skipped_count}"
  end
end