# ==============================================================================
# ApplicationController
# Base class for every controller in the app. All controllers inherit
# from here, so anything declared here applies to every action globally.
#
# Two cross-cutting concerns live here:
#   Authentication — Devise's authenticate_user! redirects unauthenticated
#     requests to the sign-in page before the action runs.
#   Authorization  — Pundit checks that the signed-in user is allowed to
#     perform the specific action on the specific record. The rescue_from
#     handler turns any policy denial into a user-friendly redirect.
# ==============================================================================
class ApplicationController < ActionController::Base
  # include mixes the Pundit module into every controller, adding the
  # authorize, policy, and policy_scope helpers as instance methods
  # available in any action.
  include Pundit::Authorization

  # before_action registers a filter that runs before every action in
  # every controller that inherits from ApplicationController.
  # authenticate_user! is provided by Devise; it checks for a valid
  # session cookie and redirects to /users/sign_in if one is not found.
  # Any controller that needs unauthenticated access (e.g. a public API)
  # would call skip_before_action :authenticate_user! to opt out.
  before_action :authenticate_user!

  # rescue_from catches the named exception anywhere in the request cycle
  # and routes it to the handler method instead of crashing with a 500.
  # Pundit raises NotAuthorizedError when a policy method returns false,
  # so this single declaration covers all policy denials app-wide.
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform that action."
    # redirect_back sends the user to the page they came from
    # (the HTTP Referer header). fallback_location is used when the
    # Referer is absent — e.g. when the request came from a bookmark
    # or a direct URL entry.
    redirect_back(fallback_location: root_path)
  end
end
