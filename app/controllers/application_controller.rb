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

  # The opening animation plays once per browser session, on whichever page
  # opens it. The session cookie remembers it has played, so the server decides
  # before any HTML is sent and the page never flashes the intro and then hides
  # it. Tests switch it off in config/environments/test.rb.
  def play_intro?
    return false if Rails.configuration.x.intro == false
    return false if session[:intro_played]

    session[:intro_played] = true
  end
end
