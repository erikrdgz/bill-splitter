Rails.application.routes.draw do
  # The quick split is the front door: no sign-up, no record yet, just a form
  # and arithmetic.
  root "splits#new"

  resources :splits, only: %i[index create show edit update] do
    resources :participants, only: %i[create update destroy]
  end

  # index is the search behind the people picker; edit and update are where a
  # saved person gets the handle you can ask them for money at.
  resources :people, only: %i[index create show edit update]

  # The organizer's own handles, so friends can pay them. Singular: there is one
  # per browser.
  resource :payment_profile, only: %i[show edit update]

  # The public share link. Short, because it gets pasted into a group chat, and
  # outside /splits because nothing here is scoped to the organizer's cookie:
  # the token is the credential.
  get "s/:share_token", to: "shares#show", as: :share
  post "s/:share_token/participants/:participant_id/payment",
       to: "payments#create", as: :share_payment

  # Returns 200 if the app boots with no exceptions. Used by hosts and uptime
  # monitors.
  get "up" => "rails/health#show", as: :rails_health_check
end
