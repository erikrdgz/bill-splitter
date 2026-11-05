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
| Quick split | `GET /` | No database at all. `QuickSplitLogic` mirrors `SplitMath` so shares move on every keystroke. |
| Split editor | `GET /splits/:id/edit` | Rename, change the total, add, name and remove people. Even and Custom modes. |
| People picker | `GET /people?participant_id=…` | Search-as-you-type in a Turbo Frame; Stimulus only debounces. |
| Share page | `GET /s/:share_token` | Public. A friend sees what they owe and taps "I paid". No account. |
| Split detail | `GET /splits/:id` | The organizer's view: who has paid, what is owed, the link to copy. |
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

## Not done yet

- Deploying to Render or Fly.io (step 9 of the build order).
- The visual design pass (step 10). The UI is deliberately plain black and white, with styling
  in Tailwind classes that are easy to replace.
