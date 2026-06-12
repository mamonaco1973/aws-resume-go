# ==============================================================================
# ApplicationPolicy
# Pundit base policy. Every resource-specific policy inherits from here.
#
# How Pundit works end-to-end:
#   1. A controller action calls `authorize @record` (or `authorize Model`
#      for collection actions like new/create where no record exists yet).
#   2. Pundit derives the policy class from the record's class name:
#      Job → JobPolicy, Resume → ResumePolicy, Folder → FolderPolicy.
#   3. Pundit instantiates the policy: PolicyClass.new(current_user, record).
#   4. Pundit calls the method matching the controller action + "?":
#        show action    → show?
#        create action  → create?
#        destroy action → destroy?
#   5. If the method returns false, Pundit raises NotAuthorizedError,
#      which ApplicationController catches and redirects gracefully.
#
# Default stance: DENY ALL. Every action returns false unless a subclass
# explicitly overrides it. A missing or incomplete policy means the action
# is blocked — the safe default for multi-tenant data where the wrong
# access grants data exposure.
# ==============================================================================
class ApplicationPolicy
  attr_reader :user, :record

  # Pundit calls initialize(current_user, @record) before each authorize.
  # Raising here if user is nil ensures that even if authenticate_user!
  # somehow did not run, an unauthenticated request is still rejected.
  def initialize(user, record)
    raise Pundit::NotAuthorizedError, "must be logged in" unless user
    @user   = user
    @record = record
  end

  def index?   = false
  def show?    = false
  def create?  = false

  # new? and edit? delegate to create? and update? respectively.
  # Rails routes the blank-form action to new? and the form submission
  # to create?. In this app they always share the same permission, so
  # delegating keeps the logic in one place.
  def new?     = create?
  def update?  = false
  def edit?    = update?
  def destroy? = false

  # ------------------------------------------------------------------------------
  # Scope
  # Used when a controller calls policy_scope(@collection) instead of
  # authorize(@record). Pundit calls Scope.new(user, Model.all).resolve
  # and uses the returned relation as the authorised collection.
  # This app scopes collections via current_user associations instead of
  # policy_scope, but the Scope class must exist to satisfy Pundit.
  # ------------------------------------------------------------------------------
  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class}#resolve not implemented"
    end

    private

    attr_reader :user, :scope
  end
end
