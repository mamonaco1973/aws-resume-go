# ==============================================================================
# AttachmentPolicy
# Authorization rules for Attachment records.
#
# create? checks the parent *job's* owner rather than the attachment
# itself, because at create time the attachment does not yet have a
# persisted id. The controller calls @job.attachments.build(…) before
# authorizing, so record.job is already set in memory.
#
# destroy? checks the attachment's own user_id column, which the
# controller sets to current_user when building the record.
# ==============================================================================
class AttachmentPolicy < ApplicationPolicy
  def create?  = record.job.user_id == user.id
  def destroy? = record.user_id == user.id
end
