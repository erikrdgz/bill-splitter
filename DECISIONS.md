# Decisions

One entry per meaningful choice, newest step last. Each entry says what was decided, why, and
what the alternative was. This doubles as interview prep: every line here is something to be
able to defend out loud.

## Step 1 — Rails 8 app with SQLite and Tailwind

### SQLite in development, Postgres only if the host requires it

SQLite is a real database here, not a toy: it enforces the same constraints, runs the same
migrations, and `Split`/`Participant`/`Person` need nothing Postgres-specific. The spec calls
for SQLite, and Rails 8 ships production-ready SQLite defaults (WAL, a connection pool per
process).

**Alternative:** Postgres from day one. Rejected because it adds a service to install and run
for zero gain at this size. The swap is a line in `Gemfile` plus `config/database.yml` if a
host like Render pushes us there, and no model or query changes.

### Import maps, not a JavaScript bundler

Rails 8's default. The browser loads ES modules straight from `vendor/javascript`, so there is
no `npm install`, no `node_modules`, and no build step for JavaScript. The spec's whole
JavaScript budget is three small Stimulus controllers, which is exactly what import maps are
for.

**Alternative:** esbuild or Vite. Rejected because a bundler earns its keep when you have a
dependency tree to flatten, and we have none.

### Tailwind through `tailwindcss-rails`, not a Node toolchain

`tailwindcss-rails` ships a standalone Tailwind v4 binary, so CSS is built by `bin/dev`
without Node being involved. Styling stays in Tailwind utility classes in the ERB, which is
what the later design pass will want to replace wholesale — markup stays semantic, classes
get swapped.

### Skipped Rails 8 frameworks that this app has no use for

Generated with `--skip-active-storage --skip-action-mailbox --skip-action-text
--skip-action-mailer --skip-solid --skip-kamal --skip-thruster`.

- No file uploads, no rich text, no inbound or outbound email (the spec puts payments, texts,
  and emails out of scope for v1).
- Solid Queue / Cache / Cable would add three databases and a dozen config files for
  background work this app does not do.
- Kamal and Thruster are for deploying to a server you rent; the spec targets Render or
  Fly.io, which have their own build step.

**Why this matters:** the goal is an app where every file can be explained in a 30-minute
walkthrough. Each skipped framework is a handful of files nobody would be able to justify.

**Kept on purpose:** Action Cable and Active Job, because the "I paid appears live on the
organizer's screen" stretch goal needs Turbo Stream broadcasts, which ride on both.

### Removed `jbuilder` and the generated `hello_controller.js`

`jbuilder` builds JSON views; every screen in this app is server-rendered HTML, and no route
answers JSON. `hello_controller.js` is the generator's demo file. Both are dead weight on day
one, and dead code in a portfolio repo reads as code you did not notice.

### Money as integer cents, decided now so nothing has to be migrated later

`total_cents` and `amount_cents` are integers. Floats cannot hold `0.01` exactly, so float
money drifts and a split stops adding up to its total — the one thing the spec says must never
happen. Formatting to dollars is a view concern.

**Alternative:** `decimal` columns. They are exact and would work, but cents keep the leftover
cent logic in rule 2 as plain integer arithmetic, with no rounding mode to reason about at
every step.

### Ruby lives in a user gem directory, not under `sudo`

Ruby 4.0.9 comes from Homebrew, and gems install to `$HOME/.gem/ruby/4.0.0` via `GEM_HOME`.
macOS also ships `/usr/bin/ruby` 2.6.10, which cannot run Rails 8, so the PATH order in
`~/.zshrc` matters. See README for the exact lines.

**Why:** installing gems with `sudo` into Homebrew's tree creates root-owned files that break
the next `brew upgrade ruby`.
