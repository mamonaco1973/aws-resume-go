# ==============================================================================
# JobsController
# Manages the full lifecycle of a scoring request. The most complex
# controller in the app due to the LinkedIn batch submission path and
# async scoring integration.
#
# On create, the controller saves a Job record and immediately enqueues
# ScoringJob via ActiveJob/Sidekiq. The HTTP response redirects before
# scoring is complete. The dashboard auto-refreshes every 5 s until all
# jobs reach a terminal status (scored or error).
# ==============================================================================
class JobsController < ApplicationController
  before_action :set_job, only: [:show, :update, :destroy]

  def index
    # Jobs have no standalone index page — the dashboard is the job list.
    # Redirecting here prevents a dead /jobs URL from rendering a blank
    # page or an authorization error.
    redirect_to dashboard_path
  end

  def show
    authorize @job
    @attachments = @job.attachments.order(created_at: :desc)
    @folders     = current_user.folders.order(:name)
  end

  def new
    authorize Job
    @job     = Job.new
    @resumes = current_user.resumes.order(:name)
    @folders = current_user.folders.order(:name)
    # Guard: if there are no resumes, the form would have an empty select
    # and any submission would fail. Redirect immediately to create one.
    redirect_to new_resume_path, alert: "Upload a resume before scoring jobs." \
      if @resumes.empty?
  end

  def create
    authorize Job

    # find_by returns nil instead of raising RecordNotFound. Scoping to
    # current_user.resumes ensures a forged resume_id from another user
    # returns nil rather than leaking data.
    resume = current_user.resumes.find_by(id: params[:job][:resume_id])

    if resume.nil?
      redirect_to new_resume_path, alert: "Add a resume before scoring jobs."
      return
    end

    # .presence converts a blank string to nil. This ensures that when no
    # folder is selected the column stores NULL, not an empty string.
    folder_id = params[:job][:folder_id].presence

    if params[:job][:source_type] == "linkedin_id"
      # --------------------------------------------------------------------
      # LinkedIn batch path
      # Each numeric ID in the textarea becomes a separate Job record.
      # ScoringJob treats the constructed LinkedIn guest API URL as a
      # regular URL fetch — no special LinkedIn handling is needed there.
      # --------------------------------------------------------------------

      # Split textarea on newlines, strip non-digits from each line,
      # discard blanks, and cap at 10 to bound both the number of
      # ScoringJob enqueues and the Bedrock token usage per submission.
      ids = params[:job][:linkedin_ids].to_s
                .lines.map { |l| l.strip.gsub(/\D/, "") }
                .reject(&:blank?)
                .first(10)

      if ids.empty?
        @job     = Job.new
        @resumes = current_user.resumes.order(:name)
        @folders = current_user.folders.order(:name)
        # flash.now scopes the message to the current render only —
        # it will not survive a redirect to the next request.
        flash.now[:alert] = "Enter at least one LinkedIn job ID."
        return render :new, status: :unprocessable_entity
      end

      ids.each do |lid|
        job = current_user.jobs.create!(
          resume:      resume,
          folder_id:   folder_id,
          source_type: "url",
          # LinkedIn guest API returns the full job posting HTML without
          # requiring authentication. ScoringJob fetches and strips it
          # the same way it handles any other URL.
          url: "https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/#{lid}"
        )
        # perform_later serialises the job id and pushes a JSON payload
        # into the Redis queue. Sidekiq picks it up in a worker process
        # and calls ScoringJob#perform(job.id). The HTTP response
        # returns before scoring is complete.
        ScoringJob.perform_later(job.id)
      end

      redirect_to dashboard_path,
        notice: "#{ids.size} LinkedIn #{"job".pluralize(ids.size)} submitted for scoring."

    else
      # --------------------------------------------------------------------
      # Single job path — URL or pasted raw text
      # --------------------------------------------------------------------
      @job        = current_user.jobs.build(job_params)
      @job.resume = resume

      if @job.save
        ScoringJob.perform_later(@job.id)
        # Redirect to the job show page so the user can watch the status
        # update in real time as ScoringJob writes progress back to the DB.
        redirect_to @job, notice: "Job submitted — scoring will begin shortly."
      else
        @resumes = current_user.resumes.order(:name)
        @folders = current_user.folders.order(:name)
        render :new, status: :unprocessable_entity
      end
    end
  end

  def update
    authorize @job
    # Both notes and folder_id are editable post-scoring via separate
    # forms on the show page. update() with the permitted params hash
    # only touches the keys that were actually submitted — the notes
    # form never sends folder_id and vice versa.
    if @job.update(job_update_params)
      redirect_to @job, notice: "Saved."
    else
      @attachments = @job.attachments.order(created_at: :desc)
      @folders     = current_user.folders.order(:name)
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @job
    @job.destroy
    redirect_to dashboard_path, notice: "Job removed."
  end

  private

  # Scope to current_user so a forged :id for another user's job raises
  # RecordNotFound (404) before Pundit even checks ownership.
  def set_job
    @job = current_user.jobs.find(params[:id])
  end

  # linkedin_ids is intentionally excluded from job_params — it is
  # processed separately in create and is never persisted directly on
  # the Job record (it becomes multiple job.url values instead).
  def job_params
    params.require(:job).permit(
      :source_type, :url, :raw_text, :folder_id, :notes
    )
  end

  # Subset used by update — source_type and url/raw_text are immutable
  # after creation; permitting them in update would let a user swap the
  # source on a scored job and silently invalidate the stored score.
  def job_update_params
    params.require(:job).permit(:notes, :folder_id)
  end
end
