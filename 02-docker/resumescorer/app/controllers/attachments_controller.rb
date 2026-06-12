# ==============================================================================
# AttachmentsController
# Manages file attachments on a Job. This is a nested resource, meaning
# attachments are always accessed in the context of their parent job.
# Routes are /jobs/:job_id/attachments and /jobs/:job_id/attachments/:id,
# so :job_id is always present in params.
#
# The nested URL structure enforces that you must know a job's id to
# attach or remove files, which limits the attack surface compared to a
# flat /attachments/:id endpoint.
# ==============================================================================
class AttachmentsController < ApplicationController
  # before_action runs set_job before every action in this controller.
  # It populates @job once, keeping the actions themselves concise and
  # ensuring every action operates on a job scoped to the current user.
  before_action :set_job

  def create
    # Build the Attachment in-memory via the job association. user is
    # set explicitly from current_user (not from params) so the foreign
    # key can never be forged. filename is taken from the upload metadata.
    @attachment = @job.attachments.build(user: current_user,
                                         filename: attachment_file.original_filename)
    authorize @attachment

    # file.attach() stages the uploaded IO object with ActiveStorage.
    # The bytes are written to S3 and the blob record is created when
    # @attachment.save is called below.
    @attachment.file.attach(attachment_file)

    if @attachment.save
      redirect_to @job, notice: "Attachment added."
    else
      # to_sentence formats ["error one", "error two"] as a readable
      # English sentence ("Error one and error two") for the flash alert.
      redirect_to @job, alert: @attachment.errors.full_messages.to_sentence
    end
  end

  def destroy
    @attachment = @job.attachments.find(params[:id])
    authorize @attachment
    # destroy removes the DB row. ActiveStorage also queues an async
    # S3 delete job (purge_later) so the HTTP response is not blocked
    # waiting for the S3 API call to complete.
    @attachment.destroy
    redirect_to @job, notice: "Attachment removed."
  end

  private

  # Scope the parent job to the current user — a forged :job_id that
  # belongs to another user raises RecordNotFound (404) here before
  # any attachment logic runs.
  def set_job
    @job = current_user.jobs.find(params[:job_id])
  end

  # params.require(:attachment).require(:file) raises
  # ActionController::ParameterMissing if the file is absent, returning
  # a 400 rather than a confusing nil error deeper in the stack.
  def attachment_file
    params.require(:attachment).require(:file)
  end
end
