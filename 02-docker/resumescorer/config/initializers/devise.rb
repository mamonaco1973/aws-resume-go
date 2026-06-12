# ==============================================================================
# Devise Configuration
# Devise is the authentication gem. This file is loaded once at startup
# as a Rails initializer. It configures password hashing, session
# behaviour, email settings, and sign-out method.
#
# Only options that differ from Devise defaults are declared here —
# anything omitted uses the gem's built-in default.
# ==============================================================================
Devise.setup do |config|
  # From address for all Devise emails (password reset, etc.). SMTP_FROM
  # is injected at container start from Secrets Manager. APP_HOST falls
  # back to "example.com" so the app boots cleanly in environments where
  # neither variable is set (local dev, CI).
  config.mailer_sender = ENV.fetch("SMTP_FROM", "noreply@#{ENV.fetch('APP_HOST', 'example.com')}")

  # Tells Devise which ORM to use for persistence. Must be explicitly
  # required here (not in Gemfile) because Devise needs ActiveRecord to
  # be fully loaded before the ORM adapter is initialised.
  require "devise/orm/active_record"

  # Normalise email to lowercase before any lookup. "User@Example.com"
  # and "user@example.com" resolve to the same account.
  config.case_insensitive_keys = [:email]

  # Strip leading/trailing whitespace from email inputs. Prevents
  # copy-paste artifacts from producing phantom duplicate accounts.
  config.strip_whitespace_keys = [:email]

  # Do not persist a session for HTTP Basic Auth requests. Keeps
  # API-style requests stateless and avoids cookie bloat.
  config.skip_session_storage = [:http_auth]

  # bcrypt cost factor. Higher = slower hash computation = harder to
  # brute-force offline. 12 is the production-safe standard; 1 is used
  # in tests for speed (bcrypt at 12 would make the test suite ~10x
  # slower with no security benefit in a test context).
  config.stretches = Rails.env.test? ? 1 : 12

  # Do not require email confirmation after changing address. Simpler
  # UX for a single-tenant demo app with no strict audit requirements.
  config.reconfirmable = false

  # Invalidate all "remember me" tokens on sign out. This means signing
  # out on one device clears persistent sessions on all devices.
  config.expire_all_remember_me_on_sign_out = true

  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  # Password reset links expire after 6 hours. After this window the
  # token is invalid and the user must request a new reset email.
  config.reset_password_within = 6.hours

  # Use GET for sign-out instead of DELETE. This app has no Turbo or
  # Rails UJS loaded in the browser. Without Turbo, every link click is
  # a plain GET — a sign_out link with data-method="delete" would just
  # navigate to the sign_out URL as a GET. Setting sign_out_via = :get
  # matches how the browser actually sends the request.
  config.sign_out_via = :get
end
