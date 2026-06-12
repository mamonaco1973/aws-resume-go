require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true

  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Serve static files from /public — ALB does not cache static assets
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  config.assets.compile = false

  config.log_level = :info
  config.log_tags = [:request_id]

  # Pipe all logs to stdout — ECS/CloudWatch captures via awslogs driver
  config.logger = ActiveSupport::Logger.new($stdout)
  config.log_formatter = ::Logger::Formatter.new

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :smtp

  # Derive host from ALB DNS — used by Devise for password reset links
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "localhost")
  }

  # SMTP credentials injected from Secrets Manager at task start
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_SERVER",   "smtp.improvmx.com"),
    port:                 ENV.fetch("SMTP_PORT",     "587").to_i,
    user_name:            ENV["SMTP_USER"],
    password:             ENV["SMTP_PASSWORD"],
    authentication:       :plain,
    enable_starttls_auto: true
  }

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
end
