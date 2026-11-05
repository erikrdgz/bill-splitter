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

## Custom split, revised — hand allocation instead of auto-evening

### The bug

Rule 3 as originally written re-evened every unlocked row on each change. Starting from
20 / 30 / 50 and dropping the first person to zero turned the other two into 50 / 50, wiping
out amounts the organizer had deliberately set. Reported as "custom doesn't work as expected",
and they were right.

### What it does now

Dragging a row sets that row and locks it. Every other row keeps what it already has, so the
money freed up by lowering someone shows up as "Left to give" for the organizer to hand out
themselves. 20 / 30 / 50 → drop the first to 0 → the other two stay at 30 and 50 with 20 left
to give, which can then go 3 to one and 17 to the other.

Rule 4 had to change with it: a slider's maximum is now the total minus **every** other row,
not just the locked ones. Untouched rows are holding cents too, so counting only locked rows
would let the amounts add up to more than the bill. This is also what makes the sliders feel
right — a row can only grow into money somebody else has let go of.

"Spread the rest evenly" is the old behavior kept as a button: the unlocked rows take an equal
share of whatever the locked rows leave. It is a shortcut the organizer asks for, rather than
something that happens behind their back.

### The server stopped recomputing custom amounts

`SplitsController#update` used to call `apply_custom_split` on every save, which would have
undone hand allocation just as surely. In custom mode it now takes the posted amounts and only
checks them; a split whose rows do not add up is refused by the validation.

**This is still "the server has the final say"** — it just says "no" instead of "here is what
you meant". Even mode is unchanged: there the amounts are the server's to work out, and
anything the form claims about them is thrown away.

### Saving is refused before it is attempted

The Save button is disabled while the remaining amount is not zero, and says what is left
instead ("$33.34 left to give"). Letting someone press Save only to be handed a validation
error is worse when the screen already knows the answer.

## Why the page used to jump to the top

Every slider release submitted the form, which redirected, which Turbo Drive handled as a full
page visit — scrolling back to the top each time, from wherever the organizer was.

Two things fixed it:

1. **Sliders no longer save on release.** With hand allocation they cannot: the split is
   usually mid-edit and would fail validation on every drag. The organizer presses Save when
   the remaining amount reaches zero.
2. **`turbo_refreshes_with method: :morph, scroll: :preserve`.** Turbo 8 treats a redirect back
   to the same page as a refresh: it morphs the changed nodes instead of replacing the body,
   and leaves the scroll alone. That fixes the same jump for the title form and the mode
   switch, which still redirect.

There is a system test that scrolls to the bottom, saves, and asserts the page did not jump —
the regression is covered rather than just fixed.

## Wording

The editor had two buttons both reading "Save", and "Remaining" did not say what it was
remaining *for*. Now:

- "Title" → "What was it for?", "Total" → "Total bill"
- "Save" → "Save name and total", beside the separate "Save amounts"
- "Remaining" → "Left to give", with "Every share has to be given out before you can save."
- "Share this split" → "Share and request money", since that page now does both

## Asking for the money

### Both directions, because they need different handles

The organizer asking a friend needs the **friend's** handle; a friend paying the organizer
needs the **organizer's**. So handles live in two places: on `people`, and on
`payment_profiles`, one row per browser.

`PaymentHandles` is a concern because this is what concerns are actually for — two models with
the same three columns, the same normalisation and the same validation rules. (Earlier in this
build I deliberately did not extract `owner_token` into a concern, because that was two lines.
This is not.)

### Real where it is free, honest where it is not

Venmo publishes a URL format that opens the app with the amount and note filled in, and Cash
App publishes one for payments. Those are real links that really work, with no API key, no
account and no approval.

Zelle has no public link format at all — it lives inside each bank's app. Apple Pay needs a
merchant account, a payment processor and server-side merchant validation. Cash App links can
send money but cannot ask for it.

Those three are built as **demonstrations**: a disclosure that shows exactly what would be
sent, says why it cannot be sent from a web page, and states that nothing has been.

**Why this matters more than it looks:** a mock dressed up as a working button is the one
genuinely harmful thing this feature could do. Somebody taps "Zelle", sees nothing happen, and
assumes the money moved. `PaymentLink#real?` is the single place that decides, and the view has
no way to render a link for something that is not.

### Apps nobody has a handle for are not shown

`PaymentLink#offerable?` hides an app unless there is a handle for it — except Apple Pay, which
belongs to the device rather than to a person. Four controls where one is useful is worse than
one.

### Handles are validated on the way in and escaped on the way out

Every handle ends up inside a URL. `PaymentHandles` restricts each format (Venmo to letters,
digits, dashes and underscores; a cashtag to a letter then alphanumerics; Zelle to an email or
phone), and `PaymentLink` escapes the handle again with `CGI.escapeURIComponent` before
interpolating. There is a test that `a b&c=d` cannot break out of the path.

Belt and braces on purpose: the validation is what gives a useful error message, and the
escaping is what holds if a validation is ever loosened.

### The batch message is the feature, not the four buttons

A bill gets settled by pasting one message into the group chat. `payment_request_message`
builds exactly that — every unpaid share, with a real link beside the ones that have one — and
the page offers it in a selectable textarea with a copy button.

### Saving a handle redraws the whole request row

A new handle means new buttons beside it. The first version replaced only the Turbo Frame
holding the handles, which left the buttons stale until a reload — caught by a system test.
The form now carries the participant it was opened from, and the answer replaces that whole
row.

## The morph tags were never on the page

`turbo_refreshes_with method: :morph, scroll: :preserve` was in the layout and did nothing at
all. The helper works through `provide :head`, which appends to a buffer that `yield :head`
has already emitted by the time the call runs — written below that line, it renders silently
into nothing.

The system test caught it only under parallel load, which is why it looked like flakiness. The
layout now calls `turbo_refresh_method_tag` and `turbo_refresh_scroll_tag` directly, so the
tags render where they are written, and the behavior was confirmed in a real browser: scrolled
to 985, saved, landed at 1061 instead of 0.

**The lesson worth keeping:** a Rails helper that returns nothing and writes to a buffer fails
silently when called in the wrong order. Checking the rendered HTML, not the template, is what
found it.

## Capybara's default wait is too short under parallel load

Passing fifty tests tipped the system suite into Minitest's parallel mode — one browser per
processor, fourteen headless Chromes on this machine. Everything still worked; the pages just
took longer to answer than Capybara's two-second default allowed, and tests failed with stale
element references on perfectly good pages.

`Capybara.default_max_wait_time = 5` is a maximum, not a pause: a test that passes immediately
still passes immediately. `assert_eventually` does the same job for values read out of
JavaScript, which Capybara's matchers cannot retry for us.

## Custom split, revised again — the sliders had no business being capped

### The bug

Reported as "the sliders still are moving together". With two people at 50/50, reducing person
A appeared to move person B's slider as well.

Person B's **amount** was never touched. Person B's **max** was: it had been capped at "the
total minus every other row", so dropping A from $50 to $30 raised B's max from 10000 to 7000
— and a range input draws its thumb at value ÷ max. B still owed exactly $50, and its thumb
slid from halfway along the track to five sevenths of the way along. Every slider looked
chained to the one being dragged.

### What it does now

Every slider runs 0 to the total, fixed, and nothing recomputes it. `#render` reads the
sliders and writes only the amounts, the percentages and the remaining figure. It never writes
a slider's value or its range — only "Spread the rest evenly" moves a slider the organizer did
not touch, and only when they ask.

So the amounts can now come to more than the bill. That is fine, and useful: the remaining
line reads "Over by $40.00" instead of "Left to give", and the Save button says `$40.00 over`
while staying shut. **The invariant was never the cap — it is the validation.** Capping the
sliders was belt on top of braces, and the belt was visibly broken.

`SplitMath.maximum_for_row` went with it. It had one caller, and rule 4 no longer exists in a
form that needs it, so leaving the method around would have been a rule nobody applies.

### The test proves itself

`test "reducing one share moves nothing about the other slider"` asserts person B's `value`
**and** its `max` are unchanged, because together those two are the thumb position. Restoring
the old dynamic max makes it fail with `Expected: "10000", Actual: "7000"` — the exact bug,
caught.

### Still open

The organizer said they often reduce someone's share because they are covering that part
themselves. Today that leaves "Left to give" above zero and the split cannot be saved. Letting
a split save with the organizer absorbing the difference would mean relaxing "participants add
up to the total", which is the hardest rule in the spec — so it is a question for them, not an
assumption to make here.

## The bill is a ceiling, not a target

Corrected after a third round of feedback, and the earlier two had it wrong in both
directions.

**The rule, in the organizer's words:** on a $100 bill you might ask $20 of one person and $30
of another and pay the remaining $50 yourself. Or ask $50 and $50. But there is never more
than $100.

So:

- **The shares may come to less than the total.** The gap is what the organizer covers, and
  the split saves that way. `participants_add_up_to_total` became
  `participants_do_not_exceed_total`. This relaxes the hardest rule in the spec, on the
  organizer's explicit instruction, and the spec was updated to match.
- **The shares may never come to more.** Enforced by clamping the row being dragged to
  whatever no one else holds, and again by the validation.

### Why clamping the dragged row is not the bug that was just fixed

The previous bug was clamping every row's `max`. That changed the *range* of sliders nobody
had touched, and a range input draws its thumb at value ÷ max — so their thumbs moved while
their amounts did not.

Clamping writes a value, to one slider, the one under the organizer's finger. Nothing else on
the page is touched. A slider that stops moving when you drag past the end of what is
available is a slider behaving normally; a slider that drifts while you drag a different one
is not.

### "Left to give" became "You pay"

The figure was always the same number; the label was describing it as an unfinished task
rather than as the organizer's own share. "You pay $50.00" is what it actually means, with
"Whatever you don't ask anyone for is yours to cover" beneath it.

The Save button is no longer disabled for a leftover — there is nothing wrong with one. It is
disabled only in the one state the sliders cannot produce: lowering the total underneath
amounts already set, which reads "Over the bill by".


## Local design pass — Connect, recent friends, and initial avatars

The Figma draft establishes the black/turquoise direction and oversized amount. The web UI
uses responsive layout rather than fixed canvas coordinates. Names sit below recent-friend
avatars so every person has a separate, readable tap target; inside share cards, names sit
beside amounts for scanning. Initials use a stable name-derived color across every screen.
There is no photo/contact data in this app, so this pass uses initials instead of invented
portraits or adding an upload feature.

Connect replaces “Save and add names.” The draft may read recent people, but still writes
nothing until Connect is pressed. The submitted IDs are resolved through the browser owner
scope, deduplicated, and applied before the server calculates shares. Choosing more friends
raises the head count. Removing a selection leaves a placeholder rather than silently
reducing the group size.

Recent quick adds reuse an unnamed seat first. A fully named group grows by one and follows
the existing even/custom allocation rules. Repeated requests for an already connected
friend are harmless. Naming uses two Turbo Stream replacements: the name and the recent
list. The other rows keep their current slider values.

### The lowered-total error needed a real browser check

A range input automatically clamps a value above its maximum. Rendering $50 shares against
a rejected $10 total therefore hid part of the excess before Stimulus could calculate it.
The error view now keeps a common fixed range large enough to hold the existing values.
It shows the actual $90 excess and disables Save amounts. Turbo morphing also keeps a
Stimulus controller alive, so a value-change callback recomputes the button state when the
total changes. Both save controls belong to the same bill form, ensuring a corrected
allocation saves the new total too. A browser regression covers the complete correction.

Validation: controller coverage for ownership, duplicate selections, quick additions, and
seat reuse; browser coverage for recent selection and the rejected-total recovery, alongside
the existing suite. No commits, pushes, deployment, or Figma writes are part of this pass.


## Corrected draft flow — Add first, Connect per person

The earlier interpretation of Connect as the primary save action was wrong. The calculator
must stand on its own: Add creates an unnamed draft row, and sliders and exact percentage
entry work before naming or persistence. The count is read-only. Recent friends append a new seat, even when unnamed seats exist. Each row's Connect dialog chooses a name and Venmo, Cash App, Zelle, or
cash. Only Save split or Review requests writes anything.

SplitDraft validates custom cents and owner-scoped people, and saves people and participants
in one transaction. A validation failure rolls back new people as well as the bill. Untouched
rows use the server's even split arithmetic. Custom rows retain their allocation and leave
the unrequested amount for the organizer. The selected payment method belongs to a participant
on this bill, while handles still belong to a person. Cash does not imply paid. Existing
provider limitations still apply; choosing a method never sends a request by itself.

### Gestures and amount entry

Cards reveal Delete on a left swipe and remove on a full swipe. Pointer handling excludes
inputs so slider dragging stays independent, and cancels on vertical movement so scrolling
works normally. Keyboard ArrowLeft reveals Delete; Delete removes a focused card. Both draft
and saved participants use the same small Stimulus controller.

Both keypads use native dialogs for focus containment and Escape dismissal. Total entry keeps
its backdrop clear and updates the existing large total live. Cancel restores the original
value. Person entry uses the dark blur, a number outside the panel, and the person's name
inside the panel. It applies only on Set amount and validates against the unclaimed balance.
Whole-dollar figures omit .00 but retain real cents. Slider gestures round to whole dollars;
exact manual entry and automatic even allocation retain cents.

Drafts start at zero and can return to zero. Saving requires at least one person. Recent
friend additions never replace an unnamed row. Saved custom additions append a zero-share
card without replacing existing cards, preserving unsaved allocations.

The visual palette is neutral graphite. Payment logos are local SVG assets from Simple Icons,
with provenance in app/assets/images/payments/README.md. No third-party asset requests run in
the browser. The original Figma frame remains inspiration, including its amount weight and
fade; no Figma changes, commits, pushes, or deployment were made.

### Mobile-only refinement

The app keeps its mobile composition on large windows. Short swipes reveal a rounded icon
button at roughly a quarter-card offset. Its red surface grows in width with the drag, then
springs back to 56px on a partial release; a release beyond 85% commits deletion. Native range
and vertical scrolling gestures stay independent. Real browser swipes cover both paths.

Draft contact search uses a read-only, owner-scoped JSON endpoint with debouncing and aborts
for stale queries. Empty search has no suggestions. Results and Create contact live below the
input without resizing the drawer. Selecting a contact fills saved payment handles; selecting
Create prepares the draft without writing yet. This is the app's saved list, not device contacts.

Shared sheet motion retains native dialogs for focus and dismissal, uses visualViewport for
software-keyboard clearance, and respects reduced motion. Underline focus expands from the
center; the bill underline is tied to its open keypad rather than residual DOM focus. Local
sample contacts can be added explicitly with the development-only dev:contacts rake task.

### Reliable backdrop dismissal

Sheets now use a full-viewport transparent dialog as the backdrop tap target and animate
only the inner content. This avoids coordinate checks against a moving native dialog.
The original event path distinguishes inside taps even when selecting a contact removes its
result button before the click bubbles. Close motion starts from the sheet's current position,
so tapping outside during entry reverses smoothly. Number edits cancel on dismissal, including
restoring the live total; Connect discards unconfirmed changes.

## A revealed swipe card closes itself after five seconds

A card swiped part-way open shows a delete button and waits. Left alone it used to wait
forever, which is wrong in two ways: it looks like something is pending, and the next tap on
that row hits a destructive control the organizer has stopped thinking about.

It now springs shut after five seconds. The timer starts in `reveal`, and is cancelled by
`close`, by the start of a fresh drag, and by `disconnect` — the last so a pending timer never
wakes up holding a card that has left the page.

### Nothing keeps it open but a full swipe or a tap

The first version carved out an exception: if focus was inside the card, the timer re-armed
instead of closing, on the theory that closing under a keyboard user would move focus
mid-decision.

That exception broke the feature outright. The card is `tabindex="0"`, so a real pointerdown
focuses it — meaning after any genuine swipe the card held focus and the timer re-armed
forever. Verified in a browser: still open at eight seconds.

The rule is the one that was asked for and no more: five seconds, closed, unless a full swipe
or a tap on the delete button is already taking the row away. Closing hides the delete button,
so if it happens to hold focus the card takes focus back — a one-line consequence of closing,
not a reason to skip it.

### The test helper was lying

None of this showed up in the tests because the synthetic `PointerEvent`s the swipe helper
dispatches do not move focus, while a real pointerdown does. The helper now calls `card.focus()`
first, so it reproduces the one property of real input that the bug depended on.

Worth remembering: a hand-rolled gesture helper is a model of the real thing, and a bug that
lives in the gap between them is invisible to every test built on it.

### Five seconds is a Stimulus value, not a constant

`revealTimeout` defaults to 5000 and the system tests shorten it to 200ms. Waiting five real
seconds in a suite that already runs eighty browser tests buys nothing, and shortening the
value exercises exactly the same code path.

The behavior was checked against the real default in a browser as well: the card read open at
4508ms and closed at 5008ms.

### The restore animation faded the card out instead of in

The flaky system test turned out to be hiding a real bug. `#restore`, which runs when the
server refuses a delete, started a fresh animation from `opacity: 1` to `opacity: 0` with
`fill: "forwards"` — its comment copy-pasted from `#exit`. So a refused deletion put the row
back and then held it invisible. The test only failed sometimes because it depended on whether
Capybara read the row before or after a 190ms fade.

It now fades from 0 to 1, and the test asserts the restored row's computed opacity directly
rather than inferring it from whether the text happened to be readable.


## Requests are the saved split's landing page

After creating a split, Rails redirects to its request screen. Unpaid people are actionable
cards; paid people appear once, below them. The message links friends to the payer view, rather
than including organizer charge links. No mock actions or developer disclosures appear in the
customer interface.

*Superseded 2026-11-05: the editor's "Save and view requests" intent and the native share sheet
are gone. Edit is now the composer (see "Editing a saved split reopens the composer"), and
"Share requests" copies the message and shows a recap (see "Share requests ends on a Shared!
recap").*


## A request is a text with a pay link, and Zelle is gone

Clicking Venmo or Cash App on a friend's row opens a pre-filled text (an `sms:` link) to the
friend's phone. The text contains a link that opens Venmo or Cash App ready to pay the *organizer*,
using the organizer's own handle and the friend's amount. Friends therefore need a phone number, not
a Venmo username: the organizer set the friends up and only chooses a payment method per person.

**Why `sms:` and not an SMS vendor.** Twilio would send from our server, but it needs an account,
costs money per message, needs sender registration in the US, and would let the app text arbitrary
numbers. An `sms:` link has none of that: the organizer's own Messages app sends it. The cost is
that we cannot tell whether it was sent, so "paid" stays a manual confirmation. A vendor is the
production upgrade, and `PaymentText` is the one place it would plug in.

**Why Zelle was removed.** It has no public API and no link format; it only exists inside banks.
Showing a "copy this email" box dressed up as an integration was not worth the space.

**Why Cash App is only ever a `:pay` link.** `cash.app/$cashtag/amount` sends money; nothing asks for
it. That fits this flow exactly, because the friend is the one paying.

**Phone numbers are stored as E.164** (`+15551230101`) and normalized on the way in, so the `sms:`
link is identical on every phone. Only punctuation is stripped: letters survive to fail validation
rather than "call me" silently turning into no number.

**Saving the organizer's handles refreshes the page** (a Turbo `refresh` stream) instead of
replacing one frame, because every request button above depends on them.

**Fake data.** The dev contacts get 555-01xx numbers (reserved for fiction) and the organizer gets
fake `erik-r` / `erikr` handles, so the whole flow can be clicked through without texting anyone.

## Friend portraits and horizontal-list discovery

The eight fictional preview contacts use a bundled, generated portrait atlas. Matching
requires the seeded name and reserved fictional phone number; ordinary contacts retain
initials. The same portrait index is used by server-rendered avatars and the draft/search
UI. No third-party avatar requests or real-person images are needed.

Recent friends fit four full items and part of the fifth. A small Stimulus controller
observes scrolling and resizing so the edge fade appears only when content remains in
that direction. The list remains a native horizontal scroller with keyboard focus.

## Compare headcounts before choosing contacts

The draft's Add person action changes headcount; Connect assigns an existing spot. Moving
recents into the drawer gives these actions distinct meanings. Selecting a recent contact
only updates drawer state until confirmation, so canceling cannot alter people or amounts.
The live comparison reads the same cents used by the cards; custom shares show a range
instead of presenting a misleading equal-share estimate. The people bucket keeps Add after its cards, allowing the list to grow while keeping
the control reachable near the viewport edge.


## Bill entry and group building share one draft

The first stage orders the total, a surface-free inline keypad, title, and Split up.
It has no separate amount confirmation. The second stage locks those bill details and
reveals the people bucket. Editing unlocks the title and amount in place; the update keypad
has a checkmark and previews changes in the existing total. No return to bill entry is needed.
SplitFlowLogic controls stages and available mobile height; QuickSplitLogic remains responsible
for allocation and connection. No stage transition saves or sends anything.

Only the people bucket scrolls. A dedicated row holds the rounded-rectangle Add button above
the persistent remainder and request area. This keeps group size from extending the whole
page. The summary groups count and per-person amount, with a quieter Split evenly button;
for one person, only the count is needed. Request split appears after a connection and opens
the existing request screen. The single form preserves the draft and server validation flow
without introducing intermediate records.

## Editing a saved split reopens the composer

Edit used to be a separate screen (recent friends, Even/Custom toggle, per-row lock) that
drifted from the new-split UI. It now renders the same `_composer` partial, already on the
people step, with the saved rows as the draft. `update` replaces the rows through SplitDraft,
the same path as `create`, so there is one set of rules. A row carries its participant id so
`paid_at` survives an edit. The lock is now only data (any hand-set amount marks a split
custom); nothing in the UI shows it.

## Review step owns Save and Request; everyone must be connected

Add person is one full-width button that never moves. Next is disabled until every person is
connected (cash counts, so there is no Venmo or Cash App requirement), then opens a review
step that holds Save split and Request split. SplitDraft refuses unconnected rows too, so a
forged request cannot skip the rule. The keypad keys live in one partial shared by the inline
keypad and the amount dialogs, so the layouts cannot drift apart.

## Share requests ends on a Shared! recap, not a share sheet

`navigator.share` opens the phone's share sheet, which is a second way to send the same thing
the per-person Text buttons already send, and it cannot tell us whether anything was sent. So
`CopyLogic#share` now copies the group message (best effort) and reveals a plain, server-rendered
**Shared!** recap already on the page: total, people requested, still owed, what you pay, and each
person's amount. Close is an ordinary link home. Nothing is marked paid and nothing claims a
message was sent, which keeps the rule that "paid" is a manual confirmation. The recap is in the
HTML from the start and only unhidden, so there is no round trip and no template in JavaScript.

## The system tests follow the composer, and some tests went away

Edit used to be its own screen, so a third of the system suite drove controls that no longer
exist: "Name Person 1", "Find a name", "Save name and total", "Save amounts", Even/Custom, the
lock checkboxes, and the Turbo Streams behind add and remove. Those were rewritten as the
composer equivalents (Connect sheet, sliders, Split evenly, Next, Save split) rather than patched
to pass, so each test still says what the user does.

Three things were deleted instead of ported, because the behavior is gone, not moved:
the device share sheet tests (replaced by a recap test), "a row with nobody named says what to
do about it" (an unconnected row can no longer be saved), and "a refused saved swipe restores
the card" (removing a card is local to the draft, so the server never refuses it).

The controller tests changed for the same reason. `PATCH /splits/:id` takes the whole draft, so
the old nested-attributes and `split_mode` tests became `draft_rows` tests, and the "row from
another split" test now proves what actually protects it: an id is only used to remember who has
paid, so a foreign id changes nothing in that split and carries no paid time over.

Shared test helpers (`save_split`, `connect_person`, `connect_everyone_with_cash`,
`edit_bill_details`, `open_editor_for`, `share_amounts`) live in `ApplicationSystemTestCase`.
A test that only cares about money connects everyone with cash, the quickest way past the rule
that every person must be connected.

Two timing flakes showed up only under parallel browsers and were fixed at the helper rather
than by retrying tests: `connect_person` re-clicks if the sheet did not open (a click that lands
while the group view is fading in can be swallowed), and the swipe auto-close in tests is 800ms
instead of 200ms so the test can look at the open card before the timer closes it.

## Still open

- Editing the total of a saved split leaves the old shares in place until **Split evenly** is
  tapped, because a reopened split is treated as custom. That is consistent, but a lowered total
  looks like an error ("Over the bill by") instead of a respread.
- A total smaller than the head count can reach Review (Next only checks "over the bill"), and
  Save then does nothing visible because the in-browser check's message sits on the hidden
  people step. The server and the browser both refuse it; the message is just not shown.
- The old row editor's controller, views and `SplitLogic` are unreferenced. Removing them is a
  separate, behavior-free cleanup.

## The Brakeman warning on the Text link is ignored, with a reason

Brakeman flags `link_to text.sms_url` in `_request_row` as "potentially unsafe model attribute
in `link_to` href" (weak confidence). The risk it guards against is a `javascript:` URL stored in
the database and rendered as a link. That cannot happen here: `PaymentText#sms_url` always starts
with the literal `sms:` scheme, the phone number is validated and stored as E.164, and the body
goes through `ERB::Util.url_encode`. Brakeman cannot see through the method call, so the warning
is recorded in `config/brakeman.ignore` with that note rather than rewriting good code to hide it
from the scanner. If `sms_url` ever builds its scheme from data, this entry must go.

The same push also loosened the "amount is centred" system test from 2px to 10px: CI's Linux
fonts draw the "$" and placeholder a few pixels wider than macOS, and the test was failing in CI
only.

## The public demo runs on Render's free tier, with sample contacts on

The demo is for showing the app, not storing anything, so it runs on a free Render web service
built from the existing Dockerfile (`render.yaml`). Free instances sleep after 15 idle minutes and
their disk is wiped on restart, so the SQLite file starts fresh each time. That is fine here:
`DEMO_MODE=true` reuses the sample contacts from local preview and seeds them per browser on the
first visit, so every visitor still gets a full contact list. The numbers are fictional 555-01xx
numbers and every request is a `sms:` link that opens the visitor's own messages app, so the site
itself never sends anything. A one-line note in the layout says so. Action Cable uses the
in-process adapter because every Turbo Stream comes back in an HTTP response; no Redis is needed.

## "I paid" confirms with a <details> element, not turbo_confirm

`turbo_confirm` asks the browser for a native `confirm()` popup. In-app browsers (a link opened
from Instagram, or an embedded preview) block those popups and quietly answer "no", so the tap
did nothing and nothing told the friend why. The row now uses a plain `<details>`: "I paid" opens
a short question and a "Yes, I paid" button, and "Not yet" closes it again. It needs no
JavaScript, so it works in every browser, and the POST and Turbo Stream behind it are unchanged.
The row was also restacked: name and amount on one line, then the pay button, then "I paid",
which is the order a friend does things in.

## Each text now ends with the share link

The individual text only carried the Venmo or Cash App link, so a friend who never saw the group
message had no way to reach "I paid". `PaymentText` now takes the share URL and appends it. The
URL is passed in from the view instead of built in the model, because building a URL needs the
request's host and a plain Ruby model should not reach for the request.

## The logo is "$plit" with a gap cut through it, and it moves in plain CSS

The trailing period is gone: "$plit" is the brand. A band in the page colour is drawn across the
middle of the word, so on the black surface it reads as a break in the letters rather than a visible
line. The nav logo and the opening animation share one partial (`shared/_wordmark`). Live text
rather than an SVG or PNG keeps it in the app's font and lets it scale with `em`.

An earlier version cut the word in two and shifted the halves sideways. It did not read well, so the
halves, the clipping and the doubled text were removed.

**No animation gem.** Motion here is CSS keyframes and transitions, plus the Web Animations API
that the bottom sheets already use. Rails has no idiomatic "motion gem", and the JS libraries
(Motion, GSAP) are for choreography this app does not have: a handful of one-shot transitions.
Staying in CSS means no new importmap pin, no bundle weight, `prefers-reduced-motion` handled in
one place, and nothing new to explain in a walkthrough. If the app ever needs spring physics or
gesture-driven timelines, that is the moment to pin `motion` through importmap.

**The intro plays once per browser session, decided by the server.** `play_intro?` flips a flag in
the session cookie, so the HTML either contains the overlay or does not. Doing this in JavaScript
(sessionStorage) would flash the overlay and then hide it on every visit. The overlay is
`data-turbo-temporary` so Turbo's Back-button snapshots never restore it, `pointer-events: none` so it
can never trap a tap, and a Stimulus controller deletes it when the fade-out ends. With reduced
motion it is not shown at all. Product call: it plays on whichever page opens the session, not only
the landing page, so a shared link still gets it once.

**Connecting a person animates a CSS class, not the render.** `#render` redraws every row on every
change (slider drags, restored drafts), so animating from inside it would replay the motion at the
wrong times. `confirmConnection` adds a `just-connected` class after the redraw instead; the
keyframes pop the portrait in, slide the name over, and flash the border once.

## Brakeman trusts sms_url by name, not by fingerprint

The Brakeman ignore for the Text link pinned a fingerprint, and that fingerprint changed as soon
as the line passed a new argument. `bin/brakeman` now declares `sms_url` safe by name with
`--url-safe-methods`, which survives edits around the call and still flags any other model
value used as a link.

## Taps never zoom: touch-action: manipulation

On iPhone, two quick taps on the same keypad digit zoomed the page instead of typing it twice.
Every control now has `touch-action: manipulation`, which keeps normal taps and pinch-zoom but
turns off double-tap zoom. The obvious alternative, `user-scalable=no` in the viewport tag, was
rejected: it also blocks pinch-zoom, which people with low vision rely on. A small test guards the
rule, since system tests cannot drive a real iPhone.

## Portraits are eight small files, preloaded; the person card has no focus ring

On a phone the connect sheet showed initials, then a portrait drawn in halfway, and motion felt
slow. The cause was one 2.4 MB sprite holding all eight portraits for avatars shown at 52 px:
it streamed in over the initials and was re-decoded during animations. It is now eight files of
about 6 KB, each picked by a CSS class (`avatar-photo--3`), and the layout preloads them in demo
mode because a closed `<dialog>` does not load its images until it opens. `#render` also stopped
rebuilding each row's avatar on every slider tick; it redraws only when the person changes.

The sheets' backdrop blur is gone too. Blurring the whole page behind a sheet every frame is a
known cause of stutter on phones, and a darker scrim reads the same.

The draft card is focusable only so arrow keys can reveal Delete. Its outline and the iOS grey
tap flash both painted over the whole card and looked broken, so both are off for the card; the
controls inside it keep their own focus styles.

## The intro plays on a first visit and after half an hour away

Once per browser session sounded right, but iOS keeps a session alive for days, so anyone coming
back never saw it again. `play_intro?` now stores when the visitor was last seen and plays the
intro on a full page load when there is no record or the gap is over 30 minutes. Turbo requests
(link visits, hover prefetches) update the clock but never play it, so it cannot cut into someone
partway through a split. Product call: 30 minutes is long enough that it never repeats during one
sitting, short enough that a link opened later in the day gets the full first impression.

## Every change of view uses one View Transition

Clicking Next swapped panels in a single frame. The composer's steps (Next, Review, Back) now
run their swap inside `document.startViewTransition`, and the layout's
`<meta name="view-transition" content="same-origin">` makes Turbo do the same for page visits.
One pair of keyframes on `::view-transition-old/new(root)` gives both the same motion: the old
view fades out fast, the new one fades in while rising 14 px. Browsers without the API fall back
to the previous panel fade, and reduced motion swaps instantly.

System tests run Chrome with `--force-prefers-reduced-motion`. A running view transition ignores
clicks, so a test that clicks the next button the moment it appears could lose the click to an
animation it does not care about.
