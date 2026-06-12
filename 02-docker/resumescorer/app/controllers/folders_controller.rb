# ==============================================================================
# FoldersController
# Standard CRUD for Folder records. Folders are purely organisational
# labels — they have no effect on scoring. The pattern here (authorize,
# build from association, strong params) is the same in every controller
# in the app; folders are the simplest example to study.
# ==============================================================================
class FoldersController < ApplicationController
  def index
    skip_authorization
    @folders = current_user.folders.order(:name)
  end

  def new
    # Passing the class (Folder) rather than an instance to authorize
    # runs the create? check. Pundit maps the new action to new?, which
    # delegates to create? in ApplicationPolicy, so both the blank-form
    # action and the form submission go through the same policy method.
    authorize Folder
    @folder = Folder.new
  end

  def create
    authorize Folder

    # current_user.folders.build(…) creates an unsaved Folder instance
    # with user_id pre-set to current_user.id. Using the association
    # scope (rather than Folder.new(…)) ensures the foreign key is always
    # correct and prevents a crafted form submission from setting an
    # arbitrary user_id.
    @folder = current_user.folders.build(folder_params)

    if @folder.save
      redirect_to folders_path, notice: "Folder created."
    else
      # Render the form again with validation error messages. 422 signals
      # that the request was understood but the submitted data was invalid.
      # The @folder instance still holds the errors populated by save.
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    # Scoping find to current_user means a forged :id that belongs to
    # another user raises ActiveRecord::RecordNotFound (→ 404) here,
    # before Pundit even runs. Pundit is a second layer of defence.
    @folder = current_user.folders.find(params[:id])
    authorize @folder
    @folder.destroy
    redirect_to folders_path, notice: "Folder deleted. Jobs were unassigned."
  end

  private

  # Strong parameters prevent mass-assignment vulnerabilities. params.require
  # raises ActionController::ParameterMissing if the :folder key is absent.
  # permit(:name) whitelists the only attribute the user is allowed to set —
  # any other field (e.g. user_id) in the form body is silently discarded.
  def folder_params
    params.require(:folder).permit(:name)
  end
end
