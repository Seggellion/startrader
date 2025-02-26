require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Make code changes take effect immediately without server restart.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Enable/disable Action Controller caching. By default Action Controller caching is disabled.
  # Run rails dev:cache to toggle Action Controller caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true
    config.public_file_server.headers = { "cache-control" => "public, max-age=#{2.days.to_i}" }
  else
    config.action_controller.perform_caching = false
  end


  config.cache_store = :memory_store

  config.active_storage.service = :local

  config.action_mailer.raise_delivery_errors = false


  config.action_mailer.perform_caching = false
  Rails.application.routes.default_url_options = { host: 'localhost', port: 3000 }


  config.active_support.deprecation = :log

  config.active_record.migration_error = :page_load

  config.active_record.verbose_query_logs = true

  config.active_record.query_log_tags_enabled = true

  config.active_job.verbose_enqueue_logs = true

  config.action_view.annotate_rendered_view_with_filenames = true


  config.action_controller.raise_on_missing_callback_actions = true



end
