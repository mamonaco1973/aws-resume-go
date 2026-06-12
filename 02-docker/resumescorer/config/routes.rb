# ==============================================================================
# Routes
# Maps every incoming HTTP request to a controller action. Rails raises
# ActionController::RoutingError (404) for any URL not declared here.
#
# URL helpers are generated automatically alongside each route. For
# example, `resources :resumes` generates resumes_path, resume_path(id),
# new_resume_path, etc. Using helpers in views and controllers rather
# than hardcoded strings means that if a path changes in this file, the
# app breaks at startup (on helper generation) rather than silently
# producing broken links at runtime.
# ==============================================================================
Rails.application.routes.draw do
  # devise_for generates all authentication routes from the Devise gem.
  # Because sign_out_via = :get is set in config/initializers/devise.rb,
  # the sign-out route is a GET rather than a DELETE. The full set:
  #   GET  /users/sign_in          → sessions#new       (sign-in form)
  #   POST /users/sign_in          → sessions#create    (authenticate)
  #   GET  /users/sign_out         → sessions#destroy   (end session)
  #   GET  /users/sign_up          → registrations#new  (sign-up form)
  #   POST /users                  → registrations#create
  #   GET  /users/password/new     → passwords#new  (forgot password form)
  #   POST /users/password         → passwords#create (send reset email)
  #   PUT  /users/password         → passwords#update (set new password)
  devise_for :users

  # root declares the homepage. GET / → DashboardController#index.
  # Generates root_path and root_url helpers.
  root "dashboard#index"

  # Named alias so dashboard_path also works alongside root_path. Using
  # a named helper is safer than hardcoding "/" — a path change only
  # needs updating here, not throughout views and controllers.
  get "dashboard", to: "dashboard#index", as: :dashboard

  # resources generates the standard RESTful route set for a resource.
  # `only:` restricts it to the listed actions — routes for edit, update,
  # etc. that are not needed are simply not created, reducing the attack
  # surface.
  #
  # resources :resumes, only: [...] generates:
  #   GET    /resumes          → resumes#index    (list all resumes)
  #   GET    /resumes/new      → resumes#new      (blank add form)
  #   POST   /resumes          → resumes#create   (save new resume)
  #   GET    /resumes/:id      → resumes#show     (view one resume's text)
  #   DELETE /resumes/:id      → resumes#destroy  (delete)
  resources :resumes, only: [:index, :new, :create, :show, :destroy]

  # resources :folders, only: [...] generates:
  #   GET    /folders          → folders#index
  #   GET    /folders/new      → folders#new
  #   POST   /folders          → folders#create
  #   DELETE /folders/:id      → folders#destroy
  resources :folders, only: [:index, :new, :create, :destroy]

  # Nested resources — attachments always live under a parent job in the
  # URL. The job_id is embedded in the path, so the controller can scope
  # the attachment to a job without an extra query parameter or hidden
  # form field.
  #
  # resources :jobs generates:
  #   GET    /jobs             → jobs#index    (redirects to dashboard)
  #   GET    /jobs/new         → jobs#new      (submission form)
  #   POST   /jobs             → jobs#create   (submit + enqueue scoring)
  #   GET    /jobs/:id         → jobs#show     (score + analysis)
  #   PATCH  /jobs/:id         → jobs#update   (save notes)
  #   DELETE /jobs/:id         → jobs#destroy  (delete job)
  #
  # resources :attachments (nested) generates:
  #   POST   /jobs/:job_id/attachments          → attachments#create
  #   DELETE /jobs/:job_id/attachments/:id      → attachments#destroy
  #
  # Helpers include: job_path(@job), new_job_path,
  #   job_attachments_path(@job), job_attachment_path(@job, @attachment)
  resources :jobs, only: [:index, :new, :create, :show, :update, :destroy] do
    resources :attachments, only: [:create, :destroy]
  end

  # Token usage summary for the current user
  get "usage", to: "dashboard#usage", as: :usage
end
