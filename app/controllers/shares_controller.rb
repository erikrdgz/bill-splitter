# The public share link. This is the one controller with no owner check, on
# purpose: the token is the credential. It is 24 random characters from
# has_secure_token, so a wrong link is a 404 rather than somebody else's bill.
#
# A friend opening this page has no account and never gets one.
class SharesController < ApplicationController
  def show
    # includes, because the page names every participant: without it this is a
    # query per row.
    @split = Split.includes(participants: :person).find_by!(share_token: params[:share_token])
    @payment_profile = PaymentProfile.find_by(owner_token: @split.owner_token)
  end
end
