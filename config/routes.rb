Rails.application.routes.draw do
  # The quick split is the front door: no sign-up, no record yet, just a form
  # and arithmetic.
  root "splits#new"

  resources :splits, only: %i[create edit update] do
    resources :participants, only: %i[create update destroy]
  end

  # index is the search behind the people picker.
  resources :people, only: %i[index create]

  # Returns 200 if the app boots with no exceptions. Used by hosts and uptime
  # monitors.
  get "up" => "rails/health#show", as: :rails_health_check
end
