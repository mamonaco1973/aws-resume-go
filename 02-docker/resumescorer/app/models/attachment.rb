# ==============================================================================
# Attachment
# A file attached to a scored job — supporting documents, cover letters,
# offer letters, etc. Stored in S3 via ActiveStorage. Validates content
# type and size to prevent abuse and keep storage costs predictable.
# ==============================================================================
class Attachment < ApplicationRecord
  belongs_to :job
  belongs_to :user

  # has_one_attached is an ActiveStorage macro. It adds a `file` accessor
  # that wraps an S3 blob. The blob metadata is stored in Rails-managed
  # tables (active_storage_blobs, active_storage_attachments), not in the
  # attachments table itself. When this Attachment record is destroyed,
  # ActiveStorage queues an async S3 deletion job (purge_later) rather
  # than blocking the HTTP request with a synchronous S3 API call.
  has_one_attached :file

  validates :filename, presence: true

  # validate (singular) registers a custom validation method. Rails calls
  # it alongside any `validates` declarations and checks whether errors
  # were added. This pattern is used when the validation logic is too
  # complex for a single validates line — here we need to inspect the
  # attached blob's content_type and byte_size.
  validate :file_content_type
  validate :file_size_limit

  private

  def file_content_type
    # Skip if no file is attached — the controller always attaches
    # before saving, so this guard only matters in tests or edge cases.
    return unless file.attached?
    allowed = %w[
      application/pdf application/msword
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      text/plain image/jpeg image/png
    ]
    unless file.content_type.in?(allowed)
      errors.add(:file, "must be a PDF, Word document, text file, or image")
    end
  end

  def file_size_limit
    return unless file.attached?
    # 10 MB cap matches the original app's per-file limit
    if file.byte_size > 10.megabytes
      errors.add(:file, "must be under 10 MB")
    end
  end
end
