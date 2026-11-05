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

## Step 2 — Migrations, models, and `SplitMath`

### `SplitMath` is a plain Ruby class of class methods, not a model or a concern

It touches no table and holds no state, so it needs neither. Class methods keep every call
self-describing at the call site — `SplitMath.even_shares(total_cents:, people_count:)` reads
the same in a controller, a test, and a code review. Its tests run with no database at all,
which is why 2,000 property-test cases finish in milliseconds.

**Alternative:** methods on `Split`. Rejected because the rules would then need a saved record
to exercise, and the browser has no `Split` to mirror them from.

### `nil` in `locked_amounts` means "this row absorbs what is left"

`custom_shares` takes one array, position-aligned with the participant list: an integer for a
locked row, `nil` for an unlocked one.

**Alternatives:** two parallel arrays (`amounts` + `locked`), which can silently fall out of
step, or a wrapper object per row, which is a class to explain for no gain. One array cannot
disagree with itself.

### A custom split clamps unlocked rows at zero instead of raising

If the locked rows already exceed the total, `custom_shares` hands the unlocked rows `0`. The
result deliberately does not add up, and `Split`'s validation is what reports that.

**Why:** the editor still has to render. If the math raised, the organizer would get an error
page in the middle of dragging a slider instead of a "remaining" figure telling them they are
over. Rule 3 says never negative; it does not say never wrong.

### "Participants add up to the total" is validated on `Split`, not `Participant`

Only the split knows the total, so only the split can judge the set. A participant on its own
cannot tell whether 3333 is right.

**Why it is a validation and not a controller check:** the spec says the server always has the
final say. A validation cannot be skipped by a second controller, a console session, or a
future Turbo Stream action.

### Check constraints in the database as a backstop

`splits` constrains `total_cents` to the allowed range and `split_mode` to the two known
values; `participants` constrains `amount_cents >= 0` and `position > 0`.

**The tradeoff:** a constraint violation raises `ActiveRecord::StatementInvalid`, which is not
something to show a user. That is fine, because the model validations cover the same ground
and produce the friendly errors. The constraints exist for the path validations do not cover —
`update_column`, `insert_all`, a console typo, a future bug. The models tell users what is
wrong; the database makes impossible money impossible. There is a test for each layer.

### Index choices follow the queries in the spec, not the columns

- `people (owner_token, name)` unique — one index doing two jobs: it enforces "name unique per
  owner", and because `owner_token` leads, it is also the index the people picker searches.
- `splits (owner_token, created_at)` — history asks for one browser's splits newest first, so
  the database can answer without a sort step.
- `participants (split_id, position)` unique — replaces the plain `split_id` index the
  generator wrote (`index: false` on the reference), because a composite index already serves
  lookups on its leading column. Two indexes where one will do is just slower writes.

### `enum ... validate: true`, so a bad form value is an error and not a crash

`split_mode` arrives from a form, and a form can send anything. Without `validate: true`,
assigning an unknown value raises `ArgumentError` — a 500 page. With it, the assignment
sticks and `valid?` returns false, which is what a controller knows how to handle.

### `has_secure_token` fills the column on `new`, not on create

Found by a failing test that expected `share_token` to be `nil` before save. Under
`load_defaults 8.1`, `config.active_record.generate_secure_token_on` is `:initialize` (changed
in Rails 7.1), so a freshly built `Split` already has its token.

**Why it matters here:** the share link can be rendered without reloading the record, and
`validates :share_token, presence: true` would be pointless. The test now asserts the real
behavior and says where it comes from, so the next person does not have to rediscover it.

### `Person has_many :participants, dependent: :nullify`

Deleting a saved person must not delete rows from past splits — that would make a finished
split stop adding up to its total. The row loses its name and falls back to its "Person 3"
placeholder, and the split's arithmetic is untouched. There is a test that asserts exactly
that.

**Alternative:** `:destroy`, which silently rewrites history, or `:restrict_with_error`, which
means a person can never be deleted once used.

### Sums are added up in Ruby, not SQL

`remaining_cents` and `owed_cents` use `participants.sum { ... }` rather than
`participants.sum(:amount_cents)`.

**Why:** the split editor needs the remaining figure for amounts the organizer has changed but
not yet saved. A SQL sum would report the old numbers and the "remaining" line would lie.

**The cost:** history renders many splits, so it must load participants with
`includes(:participants)` or it is an N+1. That belongs to step 8, and the comment in the
model says so.

### Positions are 1-based

The spec names placeholders from position ("Person 3"), so position 1 is the first person.
Zero-based positions would mean subtracting one in every view.

### Name uniqueness is case-insensitive in the model, case-sensitive in the index

The validation uses `case_sensitive: false`; the unique index is a plain one. The two
disagree only in the safe direction — the validation rejects more than the index would, so
nothing invalid gets through. Making SQLite's index case-insensitive needs `COLLATE NOCASE`,
which does not carry over to Postgres; a functional index on `LOWER(name)` is the portable fix
if a race ever actually produces a duplicate.

### The property tests use a fixed seed

The spec asks for 1,000 random totals and head counts. `Random.new(20_261_105)` makes the run
reproducible, so a failure can be debugged instead of chased. The failing total, head count,
and result are included in every assertion message.

### Fixtures describe one real scenario, not `MyString`

The generated fixtures would have violated the new unique indexes and the `split_mode` check
constraint, which is a useful sign they were never meant to be kept. They now hold a $100
dinner split three ways (3334 + 3333 + 3333), an older taxi split for history ordering, and a
third split under a different `owner_token` so the ownership boundary has something to test
against in step 4.
