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

### `test/system/.keep`, because CI ran system tests against a directory that did not exist

The generated workflow runs `bin/rails test:system`, but `rails new` does not create
`test/system` — that folder only appears when you generate a system test. The test runner then
tries to `require` the path literally and dies with `LoadError: cannot load such file --
test/system`, failing CI on the very first push.

Committing the empty directory makes the glob find nothing and pass. The first real system test
arrives with the first screen in step 3; writing one now, with no route to visit, would have
been a test of nothing.

## Step 3 — Quick split screen

### `form_with scope: :split`, not `model: @split`

There is no record behind this form. The two fields are an amount in dollars and a head count,
and neither is a column on `splits` — the server turns them into `total_cents` and a set of
participants when the split is created. `model:` would make `form_with` ask a `Split` for an
`amount` it does not have.

**Alternative:** virtual `attr_accessor :amount, :people_count` on `Split` so `model:` works.
Rejected for now: that is step 4's parsing problem, and adding writers before anything reads
them is speculative.

### The limits reach the browser as Stimulus values, never as a second copy

`SplitsController#new` reads `SplitMath::PEOPLE_RANGE` and `SplitMath::MAXIMUM_TOTAL_CENTS` and
hands them to the view, which renders them as `data-quick-split-logic-*-value` attributes.

**Why:** the spec says the browser mirrors the rules for instant feedback and the server has
the final say. Mirroring is fine; a second definition is not. If "2 to 20" were typed into the
JavaScript as well, the day somebody changes the Ruby constant is the day the stepper and the
validation start disagreeing. There is a controller test asserting the attributes match the
constants, so that drift fails the build.

### Markup stays in ERB, even the rows JavaScript adds

The share row is `_share_row.html.erb`. The server renders the rows that exist on load, and
renders the same partial once more inside a `<template>`. `QuickSplitLogic` clones that
template for rows the stepper adds.

**Why:** CLAUDE.md says the server renders HTML. A Stimulus controller building `<li>` elements
with `createElement` would put markup in two languages and guarantee they drift apart at the
design pass. Cloning a template keeps every class name in the ERB.

### A text field with `inputmode="decimal"`, not a number field, for money

It brings up the numeric keyboard on a phone, and it hands `QuickSplitLogic` the raw string so
the controller can parse digits itself. A number input would hand over a float.

### No float touches money in JavaScript either

`#amountInCents` splits the typed string on the decimal point and builds an integer; the
display is rebuilt from `Math.floor(cents / 100)` and `cents % 100`. `parseFloat` and
`(cents / 100).toFixed(2)` are both absent on purpose — the same rule as the Ruby side, kept
honestly rather than just where it is easy.

### An out-of-range head count is used immediately but corrected only on commit

Someone reaching for 12 types "1" first. Clamping on every keystroke would snap that to the
minimum of 2 and fight them. So the shares recompute with the clamped count straight away,
while the field itself is normalised on `change` — when they commit the value by leaving the
field.

**The cost:** for a moment the field and the list disagree. That is the lesser evil, and there
is a system test for the whole sequence including the correction on blur.

### Rows are added and removed, not rebuilt

`#matchRowCount` appends or removes only the difference. Rebuilding the list on every keystroke
would make the `aria-live="polite"` region re-announce all twenty rows each time a digit is
typed, which is worse than useless for a screen reader.

### Stepper buttons disable at the limits

The spec lists "2 people (minimum)" and "20 people (maximum)" as states to design. A disabled
button says so without a chip, a pill, or an error message — which the design constraints rule
out anyway.

### `Capybara.enable_aria_label = true`

The stepper buttons are a "+" and a "−", so their accessible name comes from `aria-label`.
Capybara ignores `aria-label` by default, which left the buttons unfindable and three system
tests failing. Enabling it means the tests locate those buttons exactly the way a screen reader
would — so the accessible name is now covered by tests instead of being decoration nobody
checks.

### System tests run at 375 x 812

The spec designs mobile-first at 375 px. Driving the tests at a desktop width would let a
cramped phone layout pass unnoticed.

### "Save and add names" posts to an action that does not exist yet

The button is on the screen because the spec's screen table requires it, but
`SplitsController#create` arrives in step 4. Until then, clicking it raises
`AbstractController::ActionNotFound`. This is a deliberate one-step gap, written down here so
it is a known edge and not a surprise.

## Step 4 — Save a split and edit it in Even mode

### Ownership is a signed, httponly cookie, and lookups are scoped to it

`ApplicationController#owner_token` reads a signed permanent cookie or issues a random one.
Every lookup goes through `Split.owned_by(owner_token).find(...)`.

**Why `find` on a scope rather than a check after loading:** a stranger gets
`RecordNotFound` → 404, not 403. A 403 would confirm the split exists, which is more than a
stranger should learn from a URL they guessed.

**Why httponly:** no JavaScript in this app needs the token, so no JavaScript may read it.
Signed, so a browser cannot award itself someone else's token by editing the cookie.

### The server works the shares out again on create, and never trusts the posted ones

The quick split screen has been showing amounts all along, but it does not send them. `create`
takes only the amount and the head count and calls `apply_even_split`. The spec says the server
has the final say; the cheapest way to mean it is to never accept the browser's arithmetic in
the first place.

### `DollarAmount` is the Ruby mirror of the JavaScript money parsing

`to_cents`, `format` and `to_input`, all integer-only — no `parseFloat` on one side and no
`Float` on the other. There are round-trip tests asserting that what the form shows and what
the screen shows both parse back to the cents they came from.

### A new split is named after today

The quick split has no title field, and `title` is required. Naming the split is what the
editor is for, so `create` sets "Split on November 5" and the organizer renames it.

**This is a product decision the spec left open**, recorded here rather than guessed at twice.

### The head count is clamped at 1 and at one over the maximum, and nowhere else

A forged POST asking for a million people would otherwise build a million `Participant` objects
in memory before any validation ran. Clamping to `PEOPLE_RANGE.max + 1` means an over-limit
request still fails with the message the organizer should see ("must be between 2 and 20
people"), while the work stays bounded. Clamping to the maximum itself would have silently
created a 20-person split from a request for 50.

### `has_many :participants, autosave: true`

Re-spreading the money changes every row. Without `autosave`, `split.save` would write the new
total and leave the old amounts, storing a split that does not add up — the exact thing the
validation exists to prevent. `autosave` says what is true: a split and its amounts are one
thing that saves or fails together.

### A rejected editor shows what would have been saved

When a total is refused, the form keeps the typed total and the rows show the amounts that
total would have produced. The alternative — showing the last valid amounts next to the new
total — puts two contradictory things on screen. There is a system test that follows the
rejection by reloading the editor, to prove none of it reached the database.

### A note on Capybara: `all(...)` does not wait

Two system tests failed by reading the row amounts before Turbo had swapped the page in.
`assert_selector` and `assert_text` retry until the timeout; `all` returns whatever is on the
page right now. The fix is to wait on something only the new page has — the "Saved." flash, or
the error message — before reading. Worth remembering, because the failure looks like a
server-side bug and is not one.

## Step 5 — People search, add, and remove

### One template serves both frames

`people#index` renders the row's name frame with the results frame nested inside it. Opening
the picker targets the outer frame; typing targets the inner one. Turbo takes whichever frame
it asked for out of the same response.

**Why this matters:** the obvious alternative is two endpoints — one for the picker, one for
"just the results" — which are then two templates to keep in step. Nesting them means the
search box and the list it controls can never disagree about what they are showing.

### Picking a name is a real request, not client-side state

A result is a `PATCH` to the participant that answers with the row's name frame. Nothing is
held in JavaScript between opening the picker and saving.

**Alternative:** have Stimulus write the chosen id into a hidden field and let the editor form
carry it. Rejected because the row would then show a name the database does not have yet, and
every other action on the page (adding a row, removing one) would have to know to preserve
that pending edit.

### Adding a person is one route, not two

"Add [name] as a new person" saves the `Person` and puts it on the row in a single `POST
/people`. It is one decision for the organizer, so it is one request and one undo.

### Participants are a Turbo Stream, names are a Turbo Frame

Adding or removing a row moves money in every other row, so those answer with streams that
redraw the list and the remaining total together. Naming a row changes one name and nothing
else, so that answers with a frame.

**The rule:** a frame when one region changes, a stream when several do.

### The stream replaces the whole list rather than appending one row

The spec describes appending the new row and then updating every amount. Redrawing the list as
one action does the same thing in one place. A dozen targeted actions can half-apply and leave
rows that do not add up on screen; one replace cannot. The spec's test — that the response
includes the new row — still passes.

### Removing a row renumbers the positions

Positions are what placeholders are named from, so removing the second of four would leave
"Person 1, Person 3, Person 4" on screen. `renumber_positions` assigns 1..n in ascending order,
which is safe against the unique index on `(split_id, position)`: each row moves down into a
slot the row before it has already left. `update_all` would not be safe — it gives no order
guarantee, and a descending pass would collide.

### The limits are enforced in the markup and again in the controller

The remove buttons are disabled at two people and "Add a person" is disabled at twenty, so the
screen says what is allowed. `ParticipantsController` refuses both anyway, because a disabled
button is a courtesy and not a control.

### Debounce is the only thing Stimulus does here

`PeopleSearchLogic` waits 250 ms and calls `requestSubmit`. The searching, matching and
rendering are all the server's. Submitting per keystroke would also let a slow response land
after a fast one and leave the list showing the wrong query.

`requestSubmit` rather than `submit`, because only `requestSubmit` fires the submit event, and
that event is how Turbo knows to put the response in the frame instead of the page.

### A note on Capybara: `click_on` matches links and buttons

A row named "Marissa" is a link reading "Marissa", and a picker result is a button reading
"Marissa". `click_on` found both. `click_button` and `click_link` say which one is meant.

## Step 6 — Custom split sliders

### Sliders work in cents, not dollars

The range input's `min`, `max`, `step` and `value` are all whole cents, and `step="1"` is one
cent. The browser therefore never rounds money on our behalf — there is no decimal for it to
round.

### The `form` attribute, so the sliders can live inside the rows

Each row already contains a remove button, which `button_to` renders as its own `<form>`. A
form cannot be nested in a form, so the sliders and locks carry `form="split_amounts"` and
belong to the amounts form further down the page.

**Why this over the alternatives:** turning the remove button into a link with
`data-turbo-method="delete"` makes a destructive action a link, which is worse for assistive
technology and breaks without JavaScript. Giving every row its own form would mean a request
per row and a different route than the spec's `PATCH /splits/:id`. The HTML `form` attribute is
the feature designed for exactly this, and it costs one attribute.

### The browser locks a row the moment it is dragged

Rule 3 says a row the organizer has set locks. "Set" is the first movement, not the release —
otherwise dragging one slider would make the others chase it and then snap back. The lock
checkbox is ticked on the first `input` event, and tapping it frees the row again.

### `input` moves the rows, `change` saves them

`input` fires continuously while dragging, `change` once on release. So the untouched rows
follow along live, and exactly one request is sent when the organizer lets go. The spec's "on
release, save" falls out of the two events the browser already provides.

### The server recomputes rather than trusting what the sliders posted

`SplitsController#update` reads only each row's `amount_cents` and `locked`, then calls
`apply_custom_split`. If the browser's arithmetic drifted, the server's replaces it. There is a
test that posts deliberately wrong amounts and asserts the saved rows add up to the total
anyway.

### Locked rows that overshoot are refused rather than silently clamped

If the locked rows come to more than the total, `SplitMath` gives the unlocked rows zero, the
split no longer adds up, and the validation refuses the save. The organizer sees why. Silently
scaling the locked rows down would be the app overruling an explicit instruction.

### A note on Capybara: `all(...)` is not just slow to wait, it can go stale

The earlier fix — waiting on a marker before reading the rows — was not enough. `all` returns
element handles, and if Turbo swaps the page between taking the handles and reading their text,
Selenium raises `StaleElementReferenceError`. The reads are now
`assert_row_amounts` / `assert_row_percentages` in `ApplicationSystemTestCase`, built on
`assert_selector ... text:`, which retries the whole match. The suite was run three times in a
row to confirm the flakiness is gone rather than hiding.

## Step 7 — Share page and "I paid"

### The share link has no owner check, on purpose

`SharesController` and `PaymentsController` look a split up by `share_token` and stop there.
Everywhere else in the app a lookup is scoped to the organizer's cookie; here the token *is*
the credential. That is the whole feature: a friend with the link needs no account.

What keeps it safe is that `has_secure_token` generates 24 random base58 characters, and the
route is `/s/:share_token` rather than anything derived from the id. There is a test that
opening `/s/<id>` is a 404, because a share link that could be guessed from a number would not
be a credential at all.

### A payment token is scoped to its own split

`PaymentsController` finds the participant through `@split.participants`, not through
`Participant`. One split's share link therefore cannot mark somebody on another split paid,
which it could if the participant id were looked up globally. There is a test for it.

### Paying twice is not an error

Two friends tapping the same row in a group chat is ordinary. The second tap is ignored rather
than refused, and it does not move `paid_at`. Reporting a conflict would be telling the truth
about the database and the wrong thing about the situation.

### Paid and unpaid are told apart by the row, not by a badge

The design constraints rule out chips, pills and badges. A paid row mutes and strikes through
the amount and says when it was paid; an unpaid row offers the button. Nothing depends on
colour alone, so it survives a greyscale screen and a colour-blind reader.

### The organizer's page reports, it does not act

`splits#show` renders the same row partial with `payable: false`. Marking somebody paid is
something that person does on their own share link, so the organizer's page says "Unpaid"
rather than offering a button that would speak for them.

### The copy button never claims a copy that did not happen

The share link sits in a real, readonly, selectable input. `CopyLinkLogic` tries
`navigator.clipboard`, falls back to `execCommand`, and if both fail says "Press ⌘C or Ctrl+C
to copy" instead of "Link copied."

**Why it matters:** the clipboard API needs a secure context and can be refused. A confirmation
that appears regardless is worse than no confirmation, because the organizer pastes nothing
into the group chat and does not know why. The input means the feature works with the
JavaScript switched off entirely.

## Step 8 — History

### `includes(:participants)`, with a test that fails without it

Every row in the list shows what is still owed, which adds up that split's participants.
Without eager loading that is one query per split, and the page is a list — it gets slower the
more it has to show.

`test "history does not run a query per split"` renders three splits, counts the queries,
renders six, and counts again. The counts must match. Removing the `includes` was tried: the
test fails (9 queries against 15), so it is a test that can actually catch the regression
rather than one that passes forever.

### Sliders and checkboxes are `accent-black`

Found by looking at the screen rather than by a test: Chrome renders range inputs and
checkboxes in its own blue, which is the one thing the design constraints rule out. One
Tailwind utility fixes both. Worth remembering that native form controls bring their own
colours and will not respect a palette until told to.

### History says "All paid" rather than "$0.00 owed"

A zero needs reading and comparing; "All paid" is the answer. The share page does the same
thing with "Everyone has paid."
