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
| Quick split | Amount plus Add and a read-only people count shows each share instantly. No sign-up. | $100 for 3 people shows $33.34, $33.33, $33.33, and the shares always add up to the total. |
| Name the people | Each placeholder ("Person 3") can become a saved person through search-as-you-type, or a new name added on the spot. | Searching "ma" narrows to matching saved names. A new name is saved for next time. |
| Custom split | Adjust any person's share. The leftover spreads evenly across people you haven't touched, and touched people lock. | The shares can never come to more than the total. A remaining amount is always visible, and it is the part the organizer pays themselves. The server rejects a split whose shares exceed the total. |
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
| Quick split (home) | Amount keypad, read-only people count, each person's share, a note when one person pays a cent more, an Add action, per-person Connect, custom sliders, and organizer remainder | No amount yet; 0 people in a new draft; 20 people (maximum) | Share updates on every keystroke and tap, no waiting. Add grows the group; swipe a card left to remove. A card swiped part-way open waits five seconds for a tap and then springs shut on its own, unless the keyboard is inside it. |
| Split editor | Title, total, a row per person (name or placeholder, amount, percent, slider, lock), add person, remove person, Even / Custom switch, remaining amount, Share action | Even mode; Custom mode mid-edit; error when the total doesn't add up; a row being added or removed | Dragging one slider sets that row only; everyone else stays put. Touched rows lock; tapping the lock frees them for "Spread the rest evenly". Saving is refused only when requested shares exceed the bill. |
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

Money is stored as whole cents. Requested shares plus the organizer remainder equal the bill. These rules live
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
4. **The bill is a ceiling, not a target.** Every slider's *range* runs the whole bill and
   never changes while another row is dragged. The row being dragged is clamped to whatever no
   one else is holding, so the shares can never come to more than the total — and they are
   free to come to less. What is left is what the organizer pays themselves, shown as
   "You pay $50.00", and the split saves that way.

   *Revised twice on 2026-11-05. The first attempt capped each row at the total minus every
   other row. That is arithmetically sound and visually wrong: a range input draws its thumb
   at value ÷ max, so changing one row's maximum slid its thumb without changing a cent behind
   it — every slider appeared to follow the one being dragged. Reducing one person's share
   should move nothing but that share and the remaining figure.*
5. **Cents are the source of truth.** Percentages are derived from cents. Editing a draft
   percentage converts it to whole cents and applies the same ceiling as dragging.
6. **Limits.** A draft starts with 0 people; saved splits have 1 to 20 people. The total is at least 1 cent per person and at most $99,999.99.
   No negative amounts.

   On a rejected total reduction, the sliders temporarily share a range large enough to display the existing amounts unchanged. The over-bill state blocks saving until corrected.

Currency is assumed to be US dollars for v1.

## Data model

Three tables in SQLite. A `Split` has many `Participants`; each participant may point to a
saved `Person`, or stay an unnamed placeholder.

| Table | Columns | Validations and notes |
| --- | --- | --- |
| splits | `title` (string), `total_cents` (integer), `split_mode` (even or custom), `share_token` (string, unique), `owner_token` (string), timestamps | Title required, 80 characters max. Total above 0 and at most 9,999,999. Participants add up to the total. `has_secure_token :share_token` makes the link hard to guess. |
| participants | `split_id`, `person_id` (optional), `position` (integer), `amount_cents` (integer), `locked` (boolean), `paid_at` (datetime, empty until paid), timestamps | 1 to 20 per saved split. Amount 0 or more. `position` sets list order and who gets the leftover cent. A placeholder shows "Person 3" from its position. |
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
| Save a quick split | Turbo Drive, then redirect to requests | `POST /splits` | `SplitsController#create` |
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
- Creating a split from the quick split form redirects to requests.
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


## Local design pass — revised November 5, 2026

The main circular button is **Add**: it adds an unnamed person immediately, without saving
or navigating. The first screen supports quick even splits and custom sliders. Entering
$1,000 for six people must show each share immediately. Lowering requested shares leaves
an explicit “You pay” remainder. Connect belongs to each participant, after the amounts
are visible. It identifies the person and chooses Venmo, Cash App, Zelle, or cash; it does
not send a request or mark anything paid. Reviewing requests is a separate final action.

Recent friends are one-tap additions to the draft. Names sit beneath initial avatars.
The large total uses stronger weight and a dark fade inspired by the Figma draft. Remove
instructional subtext where the controls explain themselves. Preserve meaningful validation
and honest payment-provider limitations at the request step.

Draft math runs in Stimulus and writes nothing until explicitly saved or reviewed. The
server validates submitted custom cents and all owner-scoped people. Payment method belongs
to a participant on a particular bill; contact handles stay on the saved person. Cash is an
expected payment method, not a paid status. Changes remain local for review.


### Interaction refinements

- The people count is read-only. Add is the only add control; there are no plus/minus counter buttons.
- Swipe a participant card left to reveal Delete; a full swipe removes it. Keyboard Delete
  also works from the focused card. A draft can return to zero; a saved split keeps at least
  one person. Sliders keep
  their native drag gesture and never trigger deletion.
- Drafts start empty. Add appends an unnamed card; a recent friend always appends a new card,
  even when unnamed people already exist. Connecting a friend to a specific row is separate.
- Slider gestures and arrow keys move in whole dollars. The ceiling rounds down to the
  available whole dollar. Untouched even shares retain their cent rounding. Tapping a person's
  amount allows exact cents (including zero), without changing anyone else's share.
- Tapping the total opens a dark keypad with a clear backdrop. Typing updates the existing
  large total and draft calculation live; Cancel or Escape restores the original total.
- Tapping a person's amount opens a separate dimmed, blurred view. The large number sits
  outside the keypad panel; the person's name appears inside it. Set amount applies the edit;
  Cancel or Escape discards it. An amount above the available share shows an error.
- Payment choices use locally stored Venmo, Cash App, and Zelle logos and a cash icon.
  Neutral graphite surfaces keep their brand colors and the turquoise action accent distinct.

### Mobile motion and contact selection

- Use one mobile column at every viewport width; wider windows center that same composition.
  The bill amount is centered, and its currency symbol and empty zero share the same color.
- A swipe of about a quarter of a card reveals a rounded trash icon to tap. Its red surface
  widens with the exposed space during the drag. Releasing below the delete threshold springs
  it back to a compact 56px button; releasing after at least 85% of the card width removes it directly. Sliders and vertical scrolling remain
  separate gestures. The same behavior applies to draft and saved participant cards.
- Connect starts with a blank contact search, not a list of recent names. Search the browser's
  saved contacts while typing; selecting a result loads its payment details. If the exact name
  is missing, offer Create contact inside the suggestion list. Creating here prepares the draft;
  Save split or Review requests persists it. This does not access the device address book.
- Focus on text fields expands a thin teal underline from the center. Opening a drawer focuses
  its heading, without forcing the software keyboard or a rectangular input outline. Closing
  amount entry returns focus without leaving the total's active underline behind.
- Sheets enter over 280ms and exit over 170ms; key presses and Add have restrained press feedback.
  The phone's visual viewport keeps sheets above its keyboard. Reduced-motion preferences bypass
  movement and transitions. Native focus containment and Escape dismissal remain available.
- Development preview contacts are explicit local seed data, never production defaults.

A committed swipe finishes with a short red-surface fade and a 280ms row collapse, overlapping
for a roughly 400ms exit. Remaining cards retain their DOM identity. A rejected saved deletion
restores the card; reduced-motion mode skips the exit animation.

Tapping the backdrop dismisses either number editor or Connect with the existing exit motion.
It cancels unconfirmed edits, including restoring the live total. A gesture that starts inside
the editor and ends outside does not dismiss it. Swipe exits fade the whole card before its
height becomes a thin strip, preventing clipped contents or focus outlines from flashing.

For local design review, an explicit development-only preview flag can seed each empty browser
with its own sample contacts. Existing contact lists are untouched; no records are shared across
browser owners. The flag is an ignored local file, and production never enables this behavior.


### Requests-first follow-through — November 5, 2026

Saving or reviewing a draft opens **Send requests**. A compact bill title, total, and people
count precede the unpaid request cards; each card leads with the name, amount, and chosen
payment action. Paid rows sit below the requests. Edit is a filled toolbar action, and
**Save and view requests** persists the editor before navigating.

The shared message contains outstanding amounts and the public split link, not organizer
charge links. Share requests uses the device share sheet when available, with a copyable
message fallback. Canceling the share sheet does not claim anything was sent. Cash remains
an arrangement until explicitly marked paid. Cash App requests and Zelle expose a copyable
contact and a short app instruction; unsupported Apple Pay and developer demo panels are
not offered. These replace the earlier demonstration UI described above.

### Calculation before contact selection — November 5, 2026

The people stage shows the total, live per-person result, people count, and the
large **Add person** button after the list. Even splits show an exact amount or an approximation when pennies
differ. Custom allocations show their actual minimum–maximum range, with the organizer's
remainder still available below the cards.

Recent contacts live inside the selected participant's Connect drawer. Choosing a recent
contact fills the drawer for that existing spot; only confirming connects them. It never
adds a participant or changes an allocation. Cancel leaves the draft untouched. This
supersedes the earlier draft recent-friend quick-add interaction. Search and inline creation
remain available, and contacts already in other spots cannot be selected twice.

Each draft card's identity/Connect area is a compact graphite button with a teal label,
an adjacent plus affordance, and press motion. The amount has more space and visual weight. Unnamed spots have one Person label, without a duplicate numbered avatar. Connected cards show the person's portrait
and payment method with an edit chevron. The amount remains a separate keypad action, and
swipe removal and custom sliders continue to work throughout planning and connection.


### Bill entry before the group — November 5, 2026

The first screen is amount, inline numeric keypad, title, then **Split up**, in that order.
The keypad blends into the page without a panel or key surfaces. There is no initial
checkmark: a positive amount and nonblank title enable Split up. The keypad fades out as
the group enters. No participant, contact, remainder, or request controls appear before this.

The group keeps the total and title read-only above a divider. The edit control unlocks
both on this same screen. Title editing restores its underline; tapping the amount opens
the update keypad with an integrated checkmark and previews the total in place. Dismissal
restores the original total. Done locks the details again, preserving people and allocations.

The summary groups the count above the per-person amount on the left, with a compact graphite
Split evenly button on the right. A single person shows only the count, avoiding a repeated
bill total and an equal-split action with no effect.

The group fills the available mobile viewport. Only its bounded people bucket scrolls;
the bill, summary, and actions remain in place. Add person is a rounded rectangle in a dedicated
row outside the bucket, above the persistent You pay area. Adding scrolls the bucket to the new
card. Once a person is connected, Request split appears below You pay and opens the request
screen without sending automatically. Removing the last connected person hides that action.
Swipe removal, sliders, and each person's keypad and Connect drawer retain their behavior.
