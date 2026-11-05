# The text message that asks one friend to pay the organizer. A plain Ruby rule
# with no table: it is built from a participant, the split and the organizer's
# payment profile, and it answers two questions the view needs — can this be
# sent, and what is the sms: link that sends it.
#
# The link goes to the organizer's handle, not the friend's: the friend taps it
# and Venmo or Cash App opens ready to pay. Nothing is sent from our server, so
# there is no SMS vendor, no cost and no way to text a stranger; the organizer's
# own Messages app does the sending.
class PaymentText
  def initialize(participant:, split:, payment_profile:)
    @participant = participant
    @split = split
    @payment_profile = payment_profile
  end

  # Cash has no link, so it has no text. A person added from the editor has no
  # chosen method yet, so they get the first app the organizer can be paid on
  # rather than a row that can do nothing.
  def app
    return if @participant.payment_method == "cash"

    chosen = PaymentLink::APPS.find { |candidate| candidate.to_s == @participant.payment_method }
    chosen || PaymentLink::APPS.find { |candidate| @payment_profile&.handle_for(candidate).present? && candidate != :apple_pay }
  end

  def link
    return unless app

    PaymentLink.new(app: app, handle: @payment_profile&.handle_for(app),
                    amount_cents: @participant.amount_cents, note: @split.title, direction: :pay)
  end

  def phone_number
    @participant.person&.phone_number
  end

  # Why a text cannot go out yet, as a symbol the view turns into a sentence.
  # nil means it can.
  def blocker
    return :no_person unless @participant.person
    return :cash if @participant.payment_method == "cash"
    return :no_phone if phone_number.blank?
    :no_organizer_handle unless link&.real?
  end

  def sendable?
    blocker.nil?
  end

  def body
    "Hi #{@participant.display_name.split.first}, your share of #{@split.title} is " \
      "#{DollarAmount.format(@participant.amount_cents)}. Pay with #{link.name}: #{link.url}"
  end

  # `?&body=` rather than `?body=` or `&body=`: iOS and Android each accept only
  # one of the two separators, and this form is read correctly by both.
  def sms_url
    "sms:#{phone_number}?&body=#{ERB::Util.url_encode(body)}"
  end
end
