class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :owner_token, :play_intro?

  private

  # There are no accounts. The organizer is whoever holds this cookie: a random
  # token, signed so a browser cannot award itself someone else's, and permanent
  # so a split is still theirs next month.
  #
  # Everything the organizer owns is looked up through it, which is why editing
  # somebody else's split returns 404 rather than a forbidden page — a stranger
  # should not even learn that the split exists.
  def owner_token
    @owner_token ||= cookies.signed[:owner_token] || issue_owner_token
  end

  def issue_owner_token
    token = SecureRandom.base58(24)

    cookies.signed.permanent[:owner_token] = {
      value: token,
      httponly: true, # no JavaScript needs it, so no JavaScript may read it
      same_site: :lax
    }

    token
  end

  # The opening animation plays on a visitor's first full page load, and again
  # when they come back after INTRO_AWAY of no requests. A browser session alone
  # was not enough: iOS keeps one alive for days, so a returning visitor never
  # saw it. Turbo requests (link visits, prefetches) refresh the clock but never
  # play it, so it cannot interrupt someone mid-flow. The server decides before
  # any HTML is sent, so the page never flashes the intro and then hides it.
  # Tests switch it off in config/environments/test.rb.
  INTRO_AWAY = 30.minutes

  def play_intro?
    return false if Rails.configuration.x.intro == false
    return @play_intro if defined?(@play_intro)

    last_seen = session[:last_seen_at]
    session[:last_seen_at] = Time.current.to_i
    @play_intro = full_page_load? && (last_seen.nil? || Time.current.to_i - last_seen > INTRO_AWAY)
  end

  # Turbo marks its own fetches; a typed URL, a tapped link from a text, or a
  # reload has neither header.
  def full_page_load?
    request.headers["X-Turbo-Request-Id"].blank? && request.headers["X-Sec-Purpose"].blank?
  end
end
