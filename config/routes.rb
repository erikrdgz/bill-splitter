Rails.application.routes.draw do
  # The quick split is the whole front door: no sign-up, no record yet, just a
  # form and arithmetic. Routes for the rest of the screens arrive with them.
  root "splits#new"

  resources :splits, only: %i[create]

  # Returns 200 if the app boots with no exceptions. Used by hosts and uptime
  # monitors.
  get "up" => "rails/health#show", as: :rails_health_check
end
