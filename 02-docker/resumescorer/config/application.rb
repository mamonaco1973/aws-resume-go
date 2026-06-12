require_relative "boot"

# Loads all Rails frameworks in one line: ActionController (HTTP handling),
# ActiveRecord (database ORM), ActiveJob (background jobs), ActiveStorage
# (file uploads), ActionMailer (email), and ActionView (templates).
require "rails/all"

# Activates all gems in the Gemfile that belong to the current
# Rails.groups (:default plus the current environment — :development,
# :test, or :production). Without this, required gems would need to be
# explicitly required throughout the app.
Bundler.require(*Rails.groups)

# The module name is derived from the application directory name.
# Rails uses it as a namespace for the Application class and for
# all constants autoloaded from app/.
module ResumeScorer
  class Application < Rails::Application
    # Load Rails 7.1 framework defaults. This applies a batch of
    # configuration values that the Rails team considers best practice
    # for new apps as of 7.1 — things like cookie serialiser format,
    # CSRF token format, and ActiveRecord encryption defaults. Upgrading
    # Rails later would bump this number and may require migration steps.
    config.load_defaults 7.1

    # Tell ActiveJob (Rails' queue abstraction layer) which backend to
    # use. :sidekiq routes all SomeJob.perform_later calls to Sidekiq,
    # which stores the job payload in Redis and executes it in a worker
    # process. Swapping backends (e.g. to Resque) only requires changing
    # this one line — no changes to job classes.
    config.active_job.queue_adapter = :sidekiq

    # Tell ActiveStorage which storage service to use for file uploads.
    # :amazon maps to the [amazon] block in config/storage.yml, which
    # reads the S3 bucket name and region from environment variables
    # injected by the ECS task definition at startup.
    config.active_storage.service = :amazon

    # Write application logs to stdout rather than log/production.log.
    # ECS captures all stdout/stderr output from the container and
    # forwards it to CloudWatch Logs automatically — no log rotation,
    # disk management, or log shipping configuration needed.
    config.log_level = :info
  end
end
