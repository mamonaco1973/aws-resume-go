# ==============================================================================
# ResumePolicy
# Authorization rules for Resume records. Follows the same ownership
# pattern as JobPolicy — any signed-in user can create, only the owner
# can view, update, or delete.
# ==============================================================================
class ResumePolicy < ApplicationPolicy
  def create?  = true
  def show?    = record.user_id == user.id
  def destroy? = record.user_id == user.id

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end
  end
end
