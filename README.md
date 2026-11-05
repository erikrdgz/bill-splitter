# Bill Splitter

A mobile-first web app that splits a bill in seconds. Enter an amount and a title, add the
people, and see each share move as you go. Connect each person (Venmo, Cash App or cash), review,
then text each friend a link to pay you. Friends open a public link to mark themselves paid.

Rails 8 · Hotwire (Turbo + Stimulus) · Tailwind CSS v4 · SQLite · Minitest

- [SPEC.md](SPEC.md) — what we are building and in what order.
- [DECISIONS.md](DECISIONS.md) — why each meaningful choice was made.

## Requirements

- Ruby 4.0.9 (see `.ruby-version`)
- SQLite 3

macOS ships `/usr/bin/ruby` 2.6, which cannot run Rails 8. These lines in `~/.zshrc` put
Homebrew's Ruby and the user gem directory first, so no gem ever needs `sudo`:

```sh
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH="$(/opt/homebrew/opt/ruby/bin/gem environment gemdir)/bin:$PATH"
export GEM_HOME="$HOME/.gem/ruby/4.0.0"
export PATH="$GEM_HOME/bin:$PATH"
```

Check it with `ruby -v` (expect 4.0.9) and `rails -v` (expect 8.1.x).

## Setup

```sh
bundle install
bin/rails db:prepare
```

## Run

```sh
bin/dev
```

`bin/dev` runs the Rails server and the Tailwind watcher together (see `Procfile.dev`), then
serves the app at http://localhost:3000.

## Test

```sh
bin/rails test
```

System tests, which drive a real browser, run separately:

```sh
bin/rails test:system
```

## Layout

| Path | What lives there |
| --- | --- |
| `app/models` | Active Record models, plus `SplitMath` and `DollarAmount`, plain Ruby classes holding the money rules |
| `app/controllers` | One controller per resource, kept skinny |
| `app/views` | Server-rendered ERB. Partials are named for what they show (`_share_row.html.erb`) |
| `app/javascript/controllers` | Stimulus controllers, only where the browser must react before the server can |
| `app/assets/tailwind` | Tailwind entry point; `app/assets/builds` is generated, not edited |
| `test` | Minitest, written alongside each step |

## The screens

A new split and an edit are the **same composer**: one form (`app/views/splits/_composer.html.erb`)
with three steps that share a single unsaved draft. Nothing is written until the last step.

| Screen | Route | How it works |
| --- | --- | --- |
| Bill (step 1) | `GET /` | Amount on an inline keypad, then a title, then **Split up**. Reads recent friends; writes nothing. |
| People (step 2) | same page | The bill is read-only above the group (the pencil unlocks it). **Add person** grows the group, a swipe or Delete removes a card, sliders, percentages and the keypad set a share, **Split evenly** resets them. **Connect** opens a sheet to search saved contacts, create one, or tap a recent friend, and to choose Venmo, Cash App or cash. **Next** stays disabled until everyone is connected. `QuickSplitLogic` and `SplitFlowLogic` do the previewing. |
| Review (step 3) | same page | Who pays what, and **You pay**. **Save split** or **Request split** submits the draft; either way the server redoes the math with `SplitMath` and refuses a split that does not add up. |
| Edit | `GET /splits/:id/edit` | Reopens the composer on the People step with the saved rows. `PATCH` replaces the rows through `SplitDraft`, keeping who has already paid. |
| Send requests | `GET /splits/:id` | The organizer's view. A text-with-pay-link per unpaid person, **Share requests** (copies the group message and shows a **Shared!** recap), paid rows, your own payment handles, and the split link. |
| Share page | `GET /s/:share_token` | Public. A friend sees what everyone owes and taps "I paid". No account. |
| History | `GET /splits` | This browser's splits, newest first. |
| Contacts | `GET /people/search`, `/people/:id/edit` | The search behind the Connect sheet, and the phone number a request is texted to. |

## How the money works

Every amount is a whole number of cents. `SplitMath` holds the six rules from
[SPEC.md](SPEC.md) with no database and no Rails behind it, so it is tested on its own over
thousands of random cases.

The browser mirrors those rules in `QuickSplitLogic`, purely so the numbers move before a round
trip could finish. Nothing the
browser calculates is ever stored: the server recomputes every amount with `SplitMath` and
refuses to save a split whose rows do not add up to its total.

There are no accounts. A signed, httponly, permanent cookie holds a random `owner_token`, and
every lookup is scoped to it, so another browser gets a 404 rather than someone else's bill.
The share link is the one exception: there, the token is the credential.

## Asking for the money

Connecting a person means choosing how they will pay: Venmo, Cash App or cash. Venmo and Cash
App also need a phone number, because a request is a **text message**: the organizer's own
Messages app opens with a link that takes the friend straight to Venmo or Cash App, ready to pay
the organizer the right amount. The organizer saves their own Venmo username and Cash App
$Cashtag once, on the Send requests screen.

Cash is an arrangement, not a status: a cash row says "Paying in cash" and stays unpaid until
the friend confirms on the share page. Nothing is sent from the server, so the app cannot tell
whether a text went out. Zelle and Apple Pay are not offered because neither has a public link
format.

Every handle ends up inside a URL, so it is format-checked on the way in by the
`PaymentHandles` concern and escaped again on the way out. A split cannot be saved with a
person who has not been connected, in the browser or on the server.

## Not done yet

- Deploying to Render or Fly.io (step 9 of the build order).
- A final visual design pass (step 10).
- Cleanup: the old row editor left code behind that no screen reaches any more since edit became
  the composer: `ParticipantsController`, `app/views/participants`, the `splits/_participants`,
  `_recent_friends`, `_remaining` and `_split_row` partials, the `people#index` picker views, and
  the `SplitLogic` Stimulus controller. They are still routed and tested.

For a fuller local contact preview, run `CONTACT_ID=<existing local contact ID> bin/rails dev:contacts`.
It adds eight sample names to that contact's browser-owned list, without payment handles or
new splits. The task refuses to run outside development. Connect searches saved app contacts;
it does not read a phone's address book.

For previews across browsers, `bin/rails dev:contacts:enable` opts this development server into
adding sample contacts to each empty browser-owned list on its next page load. Existing lists
are untouched, and contacts remain private to each browser. `bin/rails dev:contacts:disable`
turns off automatic sample creation. The opt-in flag lives in ignored `tmp/contact-preview.txt`;
it cannot enable samples in production.
