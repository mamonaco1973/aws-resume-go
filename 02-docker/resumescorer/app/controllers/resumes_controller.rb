# ==============================================================================
# ResumesController
# CRUD for Resume records. Resumes are plain-text pastes — no file
# upload or PDF parsing in this app. Each resume can be scored against
# many jobs. The action structure and patterns here are identical to
# FoldersController and serve as a reference for how Rails CRUD works.
# ==============================================================================
class ResumesController < ApplicationController
  def index
    skip_authorization
    @resumes = current_user.resumes.order(created_at: :desc)
  end

  def show
    # find scoped to current_user raises ActiveRecord::RecordNotFound
    # (→ 404) if the :id belongs to another user, before Pundit runs.
    # The Pundit authorize call adds a second explicit ownership check.
    @resume = current_user.resumes.find(params[:id])
    authorize @resume
  end

  def new
    authorize Resume
    # Resume.new creates an empty, unsaved instance for the form to bind
    # to. The form builder (form_with model: @resume) uses this to know
    # the form is for a new (not existing) record and should POST to
    # /resumes rather than PATCH to /resumes/:id.
    @resume = Resume.new
  end

  def create
    authorize Resume
    @resume = current_user.resumes.build(resume_params)
    if @resume.save
      redirect_to resumes_path, notice: "Resume saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @resume = current_user.resumes.find(params[:id])
    authorize @resume
    # destroy runs the before_destroy callbacks and validation, then
    # issues a DELETE. It also fires the dependent: :nullify callback on
    # the associated jobs, setting their resume_id to NULL.
    @resume.destroy
    redirect_to resumes_path, notice: "Resume deleted."
  end

  private

  def resume_params
    params.require(:resume).permit(:name, :content_text)
  end
end
