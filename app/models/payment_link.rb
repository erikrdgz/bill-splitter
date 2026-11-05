# Provider links are available only when that app supports the direction.
# Other configured methods offer manual contact copying in the view.
class PaymentLink
  # :charge asks somebody for money, :pay sends it.
  DIRECTIONS = %i[charge pay].freeze

  APPS = %i[venmo cash_app apple_pay].freeze

  NAMES = {
    venmo: "Venmo",
    cash_app: "Cash App",
    apple_pay: "Apple Pay"
  }.freeze

  # Why each one is a demonstration rather than a link, said in the interface
  # rather than buried here.
  WHY_DEMONSTRATED = {
    cash_app: "Cash App links can send money but cannot ask for it. A real request " \
              "would be made in the app.",
    apple_pay: "Apple Pay needs a merchant account and a payment processor to take money."
  }.freeze

  attr_reader :app, :handle, :amount_cents, :note, :direction

  def initialize(app:, handle:, amount_cents:, note: nil, direction: :pay)
    raise ArgumentError, "unknown app #{app.inspect}" unless APPS.include?(app)
    raise ArgumentError, "unknown direction #{direction.inspect}" unless DIRECTIONS.include?(direction)

    @app = app
    @handle = handle.presence
    @amount_cents = amount_cents.to_i
    @note = note
    @direction = direction
  end

  def name
    NAMES.fetch(app)
  end

  # Only configured methods with an available payment workflow are offered.
  def offerable?
    app != :apple_pay && handle.present?
  end

  # True only when this really opens the app with the amount filled in.
  def real?
    url.present?
  end

  def url
    return nil if handle.blank?

    case app
    when :venmo then venmo_url
    when :cash_app then cash_app_url if direction == :pay
    end
  end

  def why_demonstrated
    WHY_DEMONSTRATED[app]
  end

  # What the demonstration panel shows, and what a copied message says.
  def summary
    verb = direction == :charge ? "Request" : "Pay"

    "#{verb} #{DollarAmount.format(amount_cents)} #{direction == :charge ? 'from' : 'to'} " \
      "#{display_handle} on #{name}"
  end

  def display_handle
    return "(not set)" if handle.blank?

    case app
    when :venmo then "@#{handle}"
    when :cash_app then "$#{handle}"
    else handle
    end
  end

  private

  # Venmo's documented format: txn=charge asks, txn=pay sends, amount is a plain
  # decimal with no dollar sign, and the note is URL-escaped.
  def venmo_url
    query = {
      txn: direction == :charge ? "charge" : "pay",
      amount: dollars,
      note: note
    }.compact

    "https://venmo.com/#{escaped_handle}?#{query.to_query}"
  end

  # https://cash.app/$cashtag is Cash App's own documented share link. The
  # trailing amount is widely used and widely documented by third parties, but
  # is not in Cash App's own help pages — so it is used here, and the app never
  # claims the amount is guaranteed to arrive prefilled.
  def cash_app_url
    "https://cash.app/$#{escaped_handle}/#{dollars}"
  end

  # Validated on the way in by PaymentHandles, escaped again here. A handle
  # reaches this method from a form, and it is being pasted into a URL.
  def escaped_handle
    CGI.escapeURIComponent(handle)
  end

  def dollars
    DollarAmount.to_input(amount_cents)
  end
end
