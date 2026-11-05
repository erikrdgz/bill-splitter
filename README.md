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
| `app/models` | Active Record models, plus `SplitMath`, a plain Ruby class holding the money rules |
| `app/controllers` | One controller per resource, kept skinny |
| `app/views` | Server-rendered ERB. Partials are named for what they show (`_participant_row.html.erb`) |
| `app/javascript/controllers` | Stimulus controllers, only where the browser must react before the server can |
| `app/assets/tailwind` | Tailwind entry point; `app/assets/builds` is generated, not edited |
| `test` | Minitest, written alongside each step |
