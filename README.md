# Bill Splitter

A mobile-first web app that splits a bill in seconds. Enter an amount, set how many people,
and see each share. Optionally name the people, adjust amounts, and share a link friends open
to mark themselves paid.

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
| `app/views` | Server-rendered ERB. Partials are named for what they show (`_participant_row.html.erb`) |
| `app/javascript/controllers` | Stimulus controllers, only where the browser must react before the server can |
| `app/assets/tailwind` | Tailwind entry point; `app/assets/builds` is generated, not edited |
| `test` | Minitest, written alongside each step |

## The screens

| Screen | Route | How it works |
| --- | --- | --- |
| Quick split | `GET /` | Reads recent friends; writes only on Save split or Review requests. `QuickSplitLogic` previews even/custom shares before any save; Add grows the group and swiping removes a row. |
| Split editor | `GET /splits/:id/edit` | Rename, change the total, add, name and remove people. Even and Custom modes. |
| People picker | `GET /people?participant_id=…` | Search-as-you-type in a Turbo Frame; Stimulus only debounces. |
| Share page | `GET /s/:share_token` | Public. A friend sees what they owe and taps "I paid". No account. |
| Split detail | `GET /splits/:id` | The organizer's view: who has paid, what is owed, the link to copy, and a payment request per person. |
| History | `GET /splits` | This browser's splits, newest first. |

## How the money works

Every amount is a whole number of cents. `SplitMath` holds the six rules from
[SPEC.md](SPEC.md) with no database and no Rails behind it, so it is tested on its own over
thousands of random cases.

The browser mirrors those rules — in `QuickSplitLogic` for the quick split and `SplitLogic`
for the sliders — purely so the numbers move before a round trip could finish. Nothing the
browser calculates is ever stored: the server recomputes every amount with `SplitMath` and
refuses to save a split whose rows do not add up to its total.

There are no accounts. A signed, httponly, permanent cookie holds a random `owner_token`, and
every lookup is scoped to it, so another browser gets a 404 rather than someone else's bill.
The share link is the one exception: there, the token is the credential.

## Asking for the money

Each saved person can hold a Venmo username, Cash App $Cashtag or Zelle contact; the organizer
can hold their own. The split detail page then offers a request per unpaid person, and the
share page offers a way to pay.

Venmo and Cash App publish URL formats that open their app with the amount filled in, so those
are **real links**. Zelle has no public link format and Apple Pay needs a merchant account, so
those are **demonstrations** — a panel showing exactly what would be sent, why it cannot be
sent from a web page, and that nothing has been. `PaymentLink#real?` is the only thing that
decides which is which, so a mock can never render as a working button.

Every handle ends up inside a URL, so it is format-checked on the way in by the
`PaymentHandles` concern and escaped again on the way out.

## Not done yet

- Deploying to Render or Fly.io (step 9 of the build order).
- Review the local visual design pass (step 10): graphite surfaces, separate live-total and named-person keypads, whole-dollar draft sliders, swipe deletion, initial avatars, and per-person payment choices.

For a fuller local contact preview, run `CONTACT_ID=<existing local contact ID> bin/rails dev:contacts`.
It adds eight sample names to that contact's browser-owned list, without payment handles or
new splits. The task refuses to run outside development. Connect searches saved app contacts;
it does not read a phone's address book.

For previews across browsers, `bin/rails dev:contacts:enable` opts this development server into
adding sample contacts to each empty browser-owned list on its next page load. Existing lists
are untouched, and contacts remain private to each browser. `bin/rails dev:contacts:disable`
turns off automatic sample creation. The opt-in flag lives in ignored `tmp/contact-preview.txt`;
it cannot enable samples in production.
