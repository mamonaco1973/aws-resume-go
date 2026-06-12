# ApplicationMailer is the base class for all mailer classes in the app.
# Mailers in Rails work like controllers but produce email bodies instead
# of HTTP responses. Each public method on a mailer subclass represents
# one email type (e.g. WelcomeMailer#confirmation_email). Calling
# SomeMailer.some_method.deliver_later enqueues the email via ActiveJob.
#
# This app's emails are handled entirely by Devise (password reset, etc.)
# and inherit from Devise::Mailer, not ApplicationMailer. This class is
# the conventional stub in case custom app emails are added later.
class ApplicationMailer < ActionMailer::Base
  # default from: sets the From: header for all emails sent by subclasses.
  # Devise overrides this with its own mailer_sender setting in devise.rb.
  default from: "noreply@resumescorer.example.com"

  # layout "mailer" renders emails using app/views/layouts/mailer.html.erb
  # and mailer.text.erb, which provide consistent styling for HTML and
  # plain-text email parts respectively.
  layout "mailer"
end
