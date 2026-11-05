# Where somebody can be paid: their Venmo username, Cash App $cashtag, or the
# email or phone their bank knows them by for Zelle.
#
# Shared by Person (so the organizer can ask a friend for money) and
# PaymentProfile (so friends can pay the organizer). Two models with the same
# three columns and the same rules about them is what a concern is for.
#
# The formats are validated rather than trusted, because every one of these ends
# up inside a URL. A handle is cleaned on the way in and escaped again on the way
# out — see PaymentLink.
module PaymentHandles
  extend ActiveSupport::Concern

  # Venmo usernames are letters, digits, dashes and underscores.
  VENMO_FORMAT = /\A[A-Za-z0-9_-]{1,30}\z/
  # Cashtags start with a letter and hold letters, digits and underscores.
  CASHAPP_FORMAT = /\A[A-Za-z][A-Za-z0-9_]{0,19}\z/
  # Zelle is reached by email or phone number, because it lives inside banks.
  ZELLE_FORMAT = /\A([^@\s]+@[^@\s]+\.[^@\s]+|\+?[0-9][0-9\s().-]{6,19})\z/

  included do
    normalizes :venmo_handle, with: ->(handle) { handle.strip.delete_prefix("@").presence }
    normalizes :cashapp_cashtag, with: ->(tag) { tag.strip.delete_prefix("$").presence }
    normalizes :zelle_contact, with: ->(contact) { contact.strip.presence }

    validates :venmo_handle, format: { with: VENMO_FORMAT, message: "is not a Venmo username" },
                             allow_nil: true
    validates :cashapp_cashtag, format: { with: CASHAPP_FORMAT, message: "is not a $Cashtag" },
                                allow_nil: true
    validates :zelle_contact, format: { with: ZELLE_FORMAT,
                                        message: "is not an email address or phone number" },
                              allow_nil: true
  end

  # The handle for one app, or nil. Keeps callers from having to know which
  # column belongs to which app.
  def handle_for(app)
    case app
    when :venmo then venmo_handle
    when :cash_app then cashapp_cashtag
    when :zelle then zelle_contact
    end
  end

  def any_payment_handle?
    PaymentLink::APPS.any? { |app| handle_for(app).present? }
  end
end
