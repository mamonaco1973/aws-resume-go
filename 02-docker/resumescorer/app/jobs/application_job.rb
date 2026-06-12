# ==============================================================================
# ApplicationJob
# Base class for all background jobs. Custom job classes inherit from
# here rather than ActiveJob::Base directly — the same indirection
# pattern as ApplicationRecord and ApplicationController.
#
# ActiveJob is Rails' queue abstraction layer. It decouples job code
# from the underlying queue backend so switching from Sidekiq to another
# backend (e.g. Resque, Delayed::Job) only requires changing one line
# in config/application.rb:
#   config.active_job.queue_adapter = :sidekiq
#
# Job lifecycle:
#   1. SomeJob.perform_later(arg) serialises the class name and arguments
#      to JSON and writes the payload to the Redis queue.
#   2. A Sidekiq worker process polls Redis, deserialises the payload,
#      instantiates the job class, and calls perform(arg).
#   3. If perform raises an unhandled exception, Sidekiq retries the
#      job with exponential backoff (default: up to 25 attempts over
#      approximately 21 days before the job is moved to the dead queue).
# ==============================================================================
class ApplicationJob < ActiveJob::Base
  # Subclasses declare their target queue with queue_as :queue_name.
  # ScoringJob uses queue_as :default. Sidekiq must be configured to
  # listen on any non-default queue names used by other jobs.
end
