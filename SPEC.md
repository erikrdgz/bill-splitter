# Bill Splitter: Product and Build Spec

Nov 4, 2026 · @Erik

> Transcribed from "Bill Splitter Product and Build Spec" (PDF) so the repo carries its own
> source of truth. Change a decision here first, then tell the other side.

## How to use this doc

This is the single source of truth for two Claude sessions. The design chat owns how the app
looks and feels. The build session (Claude Code) owns how it works.

The design chat hands back: color, type, and spacing tokens; every screen at 375 px and
desktop; empty, error, and updating states; and notes on how the sliders behave. The build
session turns those into Tailwind v4 tokens and ERB views.

| Section | Owner | Read by |
| --- | --- | --- |
| Product summary, Features, User flow | Erik | Both |
| Screens and interface requirements | Design chat | Build session |
| Split math, Data model, Routes and Hotwire, Naming and tests | Build session | Design chat (for constraints) |
| Build order and open questions | Erik | Both |

## Product summary

A mobile-first web app that splits a bill in seconds. Enter an amount, set how many people,
and see each share. From there it can grow into a named split with custom amounts and a link
friends open to mark themselves paid.

### Why it exists

- A portfolio piece that shows Rails 8, Hotwire, and a real database working together.
- Prep for the Decile Group coding challenge: models, migrations, validations, and tests.
- Something Erik will actually use with friends.

### Out of scope for v1

- User accounts and login. The organizer is recognized by a signed browser cookie.
- Real payments, or sending texts and emails. The share link goes in the group chat.
- Importing phone contacts. Most browsers can't read them; "contacts" means people saved in
  the app.
- Multi-expense trip ledgers (who owes whom across a weekend). Possible v2.

## V1 features

Five features, each small on its own, that together feel like a finished product.

| Feature | What it does | Done when |
| --- | --- | --- |
| Quick split | Amount plus a people stepper (tap + or −, or type the number) shows each share instantly. No sign-up. | $100 for 3 people shows $33.34, $33.33, $33.33, and the shares always add up to the total. |
| Name the people | Each placeholder ("Person 3") can become a saved person through search-as-you-type, or a new name added on the spot. | Searching "ma" narrows to matching saved names. A new name is saved for next time. |
| Custom split | Adjust any person's share. The leftover spreads evenly across people you haven't touched, and touched people lock. | The total can never go over or under. A "remaining" amount is always visible. The server rejects a split that doesn't add up. |
| Share link | One public link per split. A friend opens it, sees what they owe, and taps "I paid." | The link works without an account. The organizer sees who has paid. A wrong link shows a not-found page. |
| History | The organizer's past splits, each with its total and how much is still owed. | Splits list newest first. An empty history invites starting a split. |
| Ask for the money | Each saved person can hold a Venmo username, Cash App $Cashtag or Zelle contact, and the organizer can hold their own. The split then offers a request per person, and the share page offers a way to pay. | A person with a Venmo username gets a real link that opens Venmo with the amount filled in. Apps that cannot carry a request from a web page say so rather than pretending. One message holds every outstanding share, to paste into a group chat. |

## User flow

Most visits can stop after the quick split. Everything after it is optional depth: name
people, adjust amounts, share, and track who paid.

## Screens and interface requirements

Six screens. This section lists what each one must contain and do; the look is the design
chat's call.

| Screen | Must contain | States to design | Interactions |
| --- | --- | --- | --- |
| Quick split (home) | Amount field, people stepper with count, each person's share, a note when one person pays a cent more, a "Save and add names" action | No amount yet; 2 people (minimum); 20 people (maximum) | Share updates on every keystroke and tap, no waiting. Stepper accepts typing too. |
| Split editor | Title, total, a row per person (name or placeholder, amount, percent, slider, lock), add person, remove person, Even / Custom switch, remaining amount, Share action | Even mode; Custom mode mid-edit; error when the total doesn't add up; a row being added or removed | Dragging one slider sets that row only; everyone else stays put. Touched rows lock; tapping the lock frees them for "Spread the rest evenly". Saving is refused until the remaining amount is zero. |
| People search | Search field, matching saved people, "Add [name] as new person" when nothing matches | No saved people yet; no matches; results | Results narrow as you type. Picking a person fills the row. |
| Share page (friend view) | Split title, total, each person and their amount, an "I paid" action on each unpaid row | Nobody paid; some paid; all paid; link not found | Tapping "I paid" asks to confirm the name, then marks it. No login. |
| Split detail (organizer) | Who has paid and who hasn't, amount still owed, copy-link action, edit action | Nothing paid; partly paid; fully paid | Copy link confirms it copied. |
| History | Each split's title, date, total, and amount still owed | Empty; a few splits; many | Tapping a split opens its detail. |

### Constraints for the design

- Mobile-first at 375 px; must also work on desktop.
- No status chips, pills, or badges. Show paid and unpaid through layout, type, or color in the
  row itself.
- Money uses tabular figures so columns line up while numbers change.
- Everything is server-rendered HTML with small JavaScript. Avoid designs that need a
  client-side app (drag-to-reorder lists, canvas charts).
- Visible keyboard focus, readable contrast, and reduced motion respected.

## Split math rules

Money is stored as whole cents, and every split adds up to the total exactly. These rules live
in one plain Ruby class, `SplitMath`, and the browser mirrors them only for instant feedback.
The server always has the final say.

1. **Whole cents only.** $100.00 is stored as `10000`. No floating-point money anywhere.
2. **Even split.** Each person gets `total ÷ people`, rounded down. The leftover cents go one
   each to the first people in list order. $100 for 3 people: 3334, 3333, 3333.
3. **Custom split.** Setting someone's amount sets that row and locks it. Everyone else keeps
   what they already have — nothing is re-evened out from under the organizer — so money freed
   up by lowering one row is theirs to hand out. "Spread the rest evenly" gives each unlocked
   row an equal share of whatever the locked rows leave, using rule 2.

   *Revised 2026-11-05. The original rule re-evened every unlocked row on each change, which
   undid allocations the organizer had already made: dropping one person of 20/30/50 to zero
   turned the other two into 50/50 instead of leaving them at 30 and 50.*
4. **No slider limit.** Every slider runs the whole bill, from zero to the total, and its
   range never changes while another row is being dragged. The amounts are free to come to
   less than the bill (the organizer is covering the rest themselves) or more (they have
   overshot).

   What keeps the total honest is the remaining amount, not a cap: it reads "Left to give"
   when the rows come to less than the bill and "Over by" when they come to more, and a split
   that does not add up cannot be saved.

   *Revised twice on 2026-11-05. The first attempt capped each row at the total minus every
   other row. That is arithmetically sound and visually wrong: a range input draws its thumb
   at value ÷ max, so changing one row's maximum slid its thumb without changing a cent behind
   it — every slider appeared to follow the one being dragged. Reducing one person's share
   should move nothing but that share and the remaining figure.*
5. **Percentages are display only.** They're worked out from cents and shown to one decimal.
   Cents are the source of truth.
6. **Limits.** 2 to 20 people. The total is at least 1 cent per person and at most $99,999.99.
   No negative amounts.

Currency is assumed to be US dollars for v1.

## Data model

Three tables in SQLite. A `Split` has many `Participants`; each participant may point to a
saved `Person`, or stay an unnamed placeholder.

| Table | Columns | Validations and notes |
| --- | --- | --- |
| splits | `title` (string), `total_cents` (integer), `split_mode` (even or custom), `share_token` (string, unique), `owner_token` (string), timestamps | Title required, 80 characters max. Total above 0 and at most 9,999,999. Participants add up to the total. `has_secure_token :share_token` makes the link hard to guess. |
| participants | `split_id`, `person_id` (optional), `position` (integer), `amount_cents` (integer), `locked` (boolean), `paid_at` (datetime, empty until paid), timestamps | 2 to 20 per split. Amount 0 or more. `position` sets list order and who gets the leftover cent. A placeholder shows "Person 3" from its position. |
| people | `name` (string), `owner_token` (string), timestamps | Name required, 40 characters max, unique per owner. Searched by name for the people picker. |

### Associations

- `Split` `has_many :participants, -> { order(:position) }, dependent: :destroy`
- `Participant` `belongs_to :split` and `belongs_to :person, optional: true`
- `Person` `has_many :participants`

### Who owns what, without accounts

On the first visit, the app sets a signed, permanent cookie holding a random `owner_token`.
Splits and people are saved with it, and only that browser can edit them. The share link is
the only way anyone else sees a split.

## Routes, controllers, and Hotwire

The server renders every screen. Stimulus is used only where the browser must react before
the server can: the quick split math, the sliders, and debouncing the search.

| Interaction | Hotwire tool | Request | Controller |
| --- | --- | --- | --- |
| Quick split shares update as you type | Stimulus only (`QuickSplitLogic`) | none | none |
| Save a quick split | Turbo Drive, then redirect to the editor | `POST /splits` | `SplitsController#create` |
| Search saved people | Stimulus debounce + Turbo Frame `people_results` | `GET /people?query=ma` | `PeopleController#index` |
| Add a person to a split | Turbo Stream: append the row, update every amount and the remaining total | `POST /splits/:id/participants` | `ParticipantsController#create` |
| Remove a person | Turbo Stream: remove the row, update amounts | `DELETE /splits/:id/participants/:id` | `ParticipantsController#destroy` |
| Drag a custom-split slider | Stimulus (`SplitLogic`) sets that row and updates the remaining total; saved when the organizer presses Save | `PATCH /splits/:id` | `SplitsController#update` |
| Open the share link | Turbo Drive page, no login | `GET /s/:share_token` | `SharesController#show` |
| Friend taps "I paid" | Turbo Stream: replace that row | `POST /s/:share_token/participants/:id/payment` | `PaymentsController#create` |
| History | Turbo Drive page | `GET /splits` | `SplitsController#index` |

```ruby
Rails.application.routes.draw do
  root "splits#new"                         # the quick split
  resources :splits, only: %i[index create show edit update] do
    resources :participants, only: %i[create destroy]
  end
  resources :people, only: %i[index create show edit update]  # index = search
  resource :payment_profile, only: %i[show edit update]      # how the organizer gets paid

  # Public share link
  get "s/:share_token", to: "shares#show", as: :share
  post "s/:share_token/participants/:participant_id/payment",
       to: "payments#create", as: :share_payment
end
```

`SplitsController#update` saves amounts with one call to `SplitMath`, so the browser and
server can never disagree for long: if they do, the server's version replaces the rows.

## Asking for the money

*Added 2026-11-05.*

Splitting the bill is half the job; collecting it is the other half. Both directions are
supported: the organizer asking each friend, and a friend paying the organizer.

| App | Request (organizer → friend) | Pay (friend → organizer) |
| --- | --- | --- |
| Venmo | Real link. `https://venmo.com/<user>?txn=charge&amount=&note=` is Venmo's own documented format. | Real link, `txn=pay`. |
| Cash App | Demonstration. A Cash App link can send money but cannot ask for it. | Real link, `https://cash.app/$<cashtag>/<amount>`. |
| Zelle | Demonstration. Zelle has no public link format; it lives inside each bank's app. | Demonstration. |
| Apple Pay | Demonstration. Needs a merchant account and a payment processor. | Demonstration. |

A demonstration is a disclosure that shows exactly what would be sent, says why it cannot be
sent from a web page, and states that nothing has been. Nothing is dressed up as working when
it is not — somebody would tap it and believe money had moved.

Handles live on `people` (so a friend can be asked) and on `payment_profiles`, one row per
browser (so the organizer can be paid). Both get the columns and the format rules from one
concern, `PaymentHandles`. Every handle ends up inside a URL, so it is validated on the way in
and escaped again on the way out.

The Cash App amount suffix is widely used but is not in Cash App's own documentation, so the
app never promises the amount will arrive prefilled.

## Naming and tests

Same convention as the Interstellar app, so every piece of a screen is easy to find. One
change: database-backed models keep Rails' own names (`Split`, not `SplitData`), because Rails
expects the class name to match the table.

| Name | What it is | Example file |
| --- | --- | --- |
| `ParticipantRow` | View (ERB partial) | `app/views/participants/_participant_row.html.erb` |
| `SplitLogic` | Browser behavior (Stimulus) | `app/javascript/controllers/split_logic_controller.js` |
| `Split` | Data with a table (Active Record model) | `app/models/split.rb` |
| `SplitMath` | Data rules without a table (plain Ruby) | `app/models/split_math.rb` |

### Tests to write (Minitest, Rails' default)

- `SplitMath`: $100 for 3 people gives 3334, 3333, 3333.
- `SplitMath`: for 1,000 random totals and head counts, the shares always add up to the total.
- `SplitMath`: custom split respects locked rows and never goes negative.
- `Split`: invalid when participants don't add up to the total, or with fewer than 2 or more
  than 20 people.
- `Split`: a share token is created on save.
- Creating a split from the quick split form redirects to the editor.
- Adding a participant answers with a Turbo Stream that includes the new row.
- The share page loads by token; a wrong token returns 404.
- "I paid" sets `paid_at` on that participant only.
- A browser with a different owner cookie can't edit someone else's split.

## Build order

The design chat needs the Quick split and Split editor screens before step 3. The rest can
follow while the build runs.

1. New Rails 8 app with SQLite and Tailwind, pushed to GitHub.
2. Migrations, models, `SplitMath`, and their tests.
3. Quick split screen.
4. Save a split and edit it in Even mode.
5. People search, add, and remove (Turbo Frame and Streams).
6. Custom split sliders.
7. Share page and "I paid."
8. History.
9. Deploy to Render or Fly.io.
10. Polish against the design, then a final pass on tests.

## Stretch goals, only if time allows

- "I paid" appears live on the organizer's screen without a refresh (Turbo Stream broadcasts).
- Real accounts with Rails 8's built-in authentication generator.
- Multi-expense trip ledger.

## Open questions

- What's the app called?
- Should friends on the share page see everyone's amounts, or only their own? Assumed:
  everyone's.
- Is 20 people the right maximum?
- US dollars only for v1? Assumed: yes.
