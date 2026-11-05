# Where the organizer gets paid. One profile per browser, edited in a Turbo
# Frame on the split detail page so saving it never takes them off the split
# they were looking at.
class PaymentProfilesController < ApplicationController
  before_action :set_payment_profile

  # Restores the display frame: what Cancel goes back to.
  def show
    render partial: "payment_profiles/payment_profile",
           locals: { payment_profile: @payment_profile }
  end

  def edit
  end

  def update
    if @payment_profile.update(payment_profile_params)
      render partial: "payment_profiles/payment_profile",
             locals: { payment_profile: @payment_profile }
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_payment_profile
    @payment_profile = PaymentProfile.for_owner(owner_token)
  end

  def payment_profile_params
    params.expect(payment_profile: %i[venmo_handle cashapp_cashtag zelle_contact])
  end
end
