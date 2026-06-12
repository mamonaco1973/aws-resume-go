# ==============================================================================
# Resume
# Stores one plain-text resume for a user. Content is pasted in by the
# user — no file upload, no PDF parsing in the app layer. Each resume
# can be scored against many jobs; deleting a resume does not delete
# those jobs, it just clears the resume_id on them (nullify).
# ==============================================================================
class Resume < ApplicationRecord
  # belongs_to declares the "child" side of a one-to-many association.
  # Rails expects a user_id integer column in the resumes table and
  # validates that it is present by default (Rails 5+). A resume with
  # no owner would be unreachable and is treated as invalid.
  belongs_to :user

  # dependent: :nullify sets job.resume_id = NULL on all jobs that
  # reference this resume when the resume is deleted. The scoring
  # history is preserved — only the reference to the source text is
  # cleared. Compare with dependent: :destroy, which would delete
  # those jobs entirely.
  has_many :jobs, dependent: :nullify

  validates :name,         presence: true

  # Minimum 50 chars prevents saving a blank or trivially short paste
  # that would produce a meaningless Bedrock score.
  validates :content_text, presence: true, length: { minimum: 50 }
end
