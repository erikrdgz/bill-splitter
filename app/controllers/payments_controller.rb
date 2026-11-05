# "I paid", from the share page. No login, same as the page it is on.
class PaymentsController < ApplicationController
  def create
    @split = Split.find_by!(share_token: params[:share_token])
    @participant = @split.participants.find(params[:participant_id])

    # Marking a row that is already paid is not an error and must not move the
    # time it was paid: two people tapping the same row in a group chat is a
    # normal Tuesday, not a conflict to report.
    @participant.update!(paid_at: Time.current) unless @participant.paid?

    render turbo_stream: [
      turbo_stream.replace(@participant,
                           partial: "payments/payment_row",
                           locals: { participant: @participant, split: @split, payable: true }),
      turbo_stream.replace("owed", partial: "shares/owed", locals: { split: @split.reload })
    ]
  end
end
