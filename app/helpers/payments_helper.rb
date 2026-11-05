module PaymentsHelper
  # The four apps for one person and one amount, in one place so the organizer's
  # side and the friend's side cannot drift apart about what is on offer.
  #
  # `payable` is whatever holds the handles: a Person when the organizer is
  # asking, their own PaymentProfile when a friend is paying.
  def payment_links_for(payable, amount_cents:, note:, direction:)
    PaymentLink::APPS.map { |app|
      PaymentLink.new(
        app: app,
        handle: payable&.handle_for(app),
        amount_cents: amount_cents,
        note: note,
        direction: direction
      )
    }.select(&:offerable?)
  end

  # One message holding every outstanding request, to paste into the group chat.
  # This is how splitting a bill actually gets settled, so it is worth more than
  # four buttons nobody taps.
  def payment_request_message(split)
    lines = split.participants.reject(&:paid?).map do |participant|
      link = payment_links_for(participant.person,
                               amount_cents: participant.amount_cents,
                               note: split.title,
                               direction: :charge).find(&:real?)

      "#{participant.display_name}: #{money(participant.amount_cents)}#{" — #{link.url}" if link}"
    end

    ([ "#{split.title} — #{money(split.total_cents)}" ] + lines).join("\n")
  end
end
