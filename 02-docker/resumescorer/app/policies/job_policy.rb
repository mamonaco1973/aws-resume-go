# ==============================================================================
# JobPolicy
# Authorization rules for Job records.
#
# The core ownership check — record.user_id == user.id — is the primary
# guard against horizontal privilege escalation: one user accessing
# another user's jobs via a crafted URL like /jobs/999.
# ==============================================================================
class JobPolicy < ApplicationPolicy
  # Any signed-in user may create a job. There is no existing record to
  # check ownership against at create time — the job does not exist yet.
  def create?  = true

  # All other actions verify that the job belongs to the requesting user.
  # record is the Job instance; user is current_user from the session.
  def show?    = record.user_id == user.id
  def update?  = record.user_id == user.id
  def destroy? = record.user_id == user.id

  # Scope is available if policy_scope is ever called on a Job relation.
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end
  end
end
