# ==============================================================================
# Job
# Represents one resume-vs-job scoring request. Tracks the full lifecycle
# from submission through async Sidekiq processing to a final score and
# written analysis.
#
# Status flow:
#   pending → scoring → scored
#                    ↘ error
#
# A Job must supply either a URL (which ScoringJob fetches and parses)
# or raw_text (which is scored directly). folder_id is optional.
# ==============================================================================
class Job < ApplicationRecord
  belongs_to :user
  belongs_to :resume

  # optional: true allows folder_id to be NULL — a job does not need to
  # belong to a folder. Without this, Rails would validate folder_id
  # presence and reject unfiled jobs.
  belongs_to :folder, optional: true

  # dependent: :destroy — deleting a Job cascades to its Attachment rows
  # and, via ActiveStorage, to the corresponding S3 blobs.
  has_many :attachments, dependent: :destroy

  # Plain string constant rather than a Rails enum. Enum would store
  # integers and add auto-generated helpers (job.scored!, job.pending?)
  # but also makes the database values opaque. Plain strings keep the
  # schema human-readable when querying the database directly.
  STATUSES = %w[pending scoring scored error].freeze

  validates :source_type, inclusion: { in: %w[url raw_text] }

  # Conditional validations — only the field matching source_type must be
  # present. The lambda (-> { }) defers evaluation so each record is
  # checked at save time with its own source_type value.
  validates :url,      presence: true, if: -> { source_type == "url" }
  validates :raw_text, presence: true, if: -> { source_type == "raw_text" }

  # Named scopes are reusable, chainable query fragments. They return an
  # ActiveRecord::Relation (not an Array), so additional scopes, ordering,
  # and limits can be appended without extra queries. Rails only executes
  # the SQL when the result is actually iterated (lazy evaluation).

  # Order newest-first — used everywhere jobs are listed.
  scope :recent,    -> { order(created_at: :desc) }

  # Used for the "scored" dashboard filter.
  scope :scored,    -> { where(status: "scored") }

  # Covers both "pending" (queued, not started) and "scoring" (worker
  # is actively running). Used by the dashboard auto-refresh check.
  scope :pending,   -> { where(status: %w[pending scoring]) }

  # When fid is blank the scope returns the full relation unchanged,
  # so the caller can chain it unconditionally without an if/else branch.
  scope :in_folder, ->(fid) { where(folder_id: fid) if fid.present? }

  # ILIKE is PostgreSQL's case-insensitive LIKE. Parameterised placeholders
  # (?) prevent SQL injection — never interpolate user input directly into
  # a SQL string. The scope is a no-op when q is blank.
  scope :by_keyword, ->(q) {
    where("title ILIKE ? OR company ILIKE ?", "%#{q}%", "%#{q}%") \
      if q.present?
  }

  # Predicate helpers used in views and ScoringJob. Centralising these
  # checks prevents status string literals from being scattered across
  # the codebase — a typo here fails fast at the model layer.

  def scored?
    status == "scored"
  end

  # processing? returns true for both "pending" (enqueued, not yet
  # picked up by Sidekiq) and "scoring" (worker is running). Both mean
  # the job is in-flight and the dashboard should keep auto-refreshing.
  def processing?
    status.in?(%w[pending scoring])
  end

  def errored?
    status == "error"
  end

  # Returns a colour name string used to select Tailwind CSS classes
  # for the score badge ring on the dashboard (green/yellow/red).
  def score_color
    return "gray" unless scored? && score
    if score >= 75 then "green"
    elsif score >= 50 then "yellow"
    else "red"
    end
  end
end
