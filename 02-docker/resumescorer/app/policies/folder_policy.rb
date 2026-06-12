# ==============================================================================
# FolderPolicy
# Authorization rules for Folder records.
# ==============================================================================
class FolderPolicy < ApplicationPolicy
  def create?  = true
  def destroy? = record.user_id == user.id

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end
  end
end
