# ==============================================================================
# DashboardController
# Serves the app's home page — the full job list with search/folder
# filters and the Bedrock token usage ring. This is the first screen
# a signed-in user sees after authentication.
# ==============================================================================
class DashboardController < ApplicationController
  def index
    # skip_authorization tells Pundit that this action intentionally has
    # no policy check. Pundit raises an error at the end of any action
    # that neither calls authorize() nor skip_authorization(), so this
    # must be explicit rather than simply absent. The dashboard only
    # shows the current user's own data (scoped via current_user), so
    # a per-record policy check would be redundant.
    skip_authorization

    # current_user is provided by Devise. It loads the User record for
    # the active session (via session[:user_id]). All queries start from
    # current_user so one user can never access another user's records.
    #
    # .includes(:resume, :folder) is eager loading. Without it, rendering
    # job.resume.name and job.folder.name for each row would fire one
    # extra SQL query per job — the "N+1 query" problem. includes()
    # fetches all associated resumes and folders in two additional queries
    # up front, regardless of how many jobs are in the list.
    #
    # Named scopes are chained here. Each scope appends to the same SQL
    # query; Rails executes the query lazily — only when the view actually
    # iterates @jobs, not when these lines run.
    @jobs    = current_user.jobs
                 .includes(:resume, :folder)
                 .recent
                 .in_folder(params[:folder_id])
                 .by_keyword(params[:q])

    @folders = current_user.folders.order(:name)
    @resumes = current_user.resumes.order(:name)
  end

  def usage
    skip_authorization
    @user = current_user
  end
end
