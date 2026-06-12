# ==============================================================================
# User
# Represents one authenticated account. Devise handles password hashing,
# session management, and password-reset emails. Every other resource
# (resumes, jobs, folders, attachments) has a user_id foreign key so
# users can never see each other's data.
# ==============================================================================
class User < ApplicationRecord
  # devise() is a macro that mixes authentication modules into the model.
  # Each symbol enables a distinct feature:
  #
  #   :database_authenticatable — stores a bcrypt-hashed password in the
  #     encrypted_password column; validates credentials on sign-in.
  #
  #   :registerable — allows self-service sign-up via /users/sign_up.
  #
  #   :recoverable — generates a time-limited token and emails a
  #     password-reset link when the user clicks "Forgot password".
  #
  #   :rememberable — writes a signed "remember me" cookie so the
  #     session survives after the browser is closed.
  #
  #   :validatable — adds email format and minimum password length
  #     validations automatically; no need to declare them manually.
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # has_many declares the "parent" side of a one-to-many association.
  # Rails infers the foreign key as user_id on each child table
  # (resumes.user_id, jobs.user_id, etc.).
  #
  # dependent: :destroy means that deleting a User also deletes all its
  # associated child rows. This keeps the database free of orphaned
  # records — a resume with no owner, for example, could never be
  # accessed and would just waste storage.
  has_many :resumes,     dependent: :destroy
  has_many :folders,     dependent: :destroy
  has_many :jobs,        dependent: :destroy
  has_many :attachments, dependent: :destroy

  # Returns true when the user has consumed all their Bedrock token budget.
  # Called by ScoringJob before each API call to enforce the per-user cap.
  def over_token_limit?
    tokens_used >= token_limit
  end

  # Returns the percentage of the token budget consumed, clamped to 100.
  # Drives the SVG ring chart rendered on the dashboard.
  def token_usage_pct
    # Guard against division by zero if token_limit is somehow 0.
    return 0 if token_limit.zero?
    [(tokens_used.to_f / token_limit * 100).round, 100].min
  end
end
