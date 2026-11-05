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

A mobile-first web app that splits a bill in seconds. Enter an amount and a title, add the
people, and see each share. From there it grows into a connected split with custom amounts, a
text per friend with a link to pay you, and a link friends open to mark themselves paid.

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
| Quick split | Amount, title and an Add person button with a read-only people count show each share instantly. No sign-up. | $100 for 3 people shows $33.34, $33.33, $33.33, and the shares always add up to the total. |
| Connect the people | Each placeholder ("Person 3") is connected to a saved contact through search-as-you-type, a recent friend, or a new name created on the spot, and given a way to pay: Venmo, Cash App or cash. Everyone must be connected before a split can be reviewed or saved. | Searching "ma" narrows to matching saved names. A new name is saved for next time. A split with an unconnected person is refused by the browser and by the server. |
| Custom split | Adjust any person's share by slider, percentage or keypad. Setting a share holds it; Split evenly gives every row back to the spread. | The shares can never come to more than the total. A remaining amount is always visible, and it is the part the organizer pays themselves. The server rejects a split whose shares exceed the total. |
| Share link | One public link per split. A friend opens it, sees what they owe, and taps "I paid." | The link works without an account. The organizer sees who has paid. A wrong link shows a not-found page. |
| History | The organizer's past splits, each with its total and how much is still owed. | Splits list newest first. An empty history invites starting a split. |
| Ask for the money | Each connected person holds a phone number and the way they will pay (Venmo, Cash App or cash); the organizer saves their own Venmo username and Cash App $Cashtag. The split then offers a text per person containing a link to pay the organizer, and the share page offers the same link. | A Venmo or Cash App friend gets a text that opens the right app with the amount filled in. Cash says "Paying in cash". One message holds every outstanding share, to paste into a group chat. |

## User flow

Most visits can stop after the quick split. Everything after it is optional depth: name
people, adjust amounts, share, and track who paid.

## Screens and interface requirements

Six screens, the first three being steps of one composer. This section lists what each one
must contain and do; the look is the design chat's call.

| Screen | Must contain | States to design | Interactions |
| --- | --- | --- | --- |
| Bill (composer step 1, home) | Amount with an inline keypad, a title, and Split up | No amount or title yet (Split up disabled) | The keypad updates the amount as you tap. Split up needs a positive amount and a title. |
| People (composer step 2) | Read-only bill header with an edit control, the people count, each person's share, a note when one person pays a cent more, Split evenly, per-person Connect, sliders, percentage and keypad amount, Add person, You pay, Next | 0 people in a new draft; someone not yet connected (Next disabled); over the bill (Next disabled); 20 people (maximum) | Share updates on every keystroke and tap, no waiting. Add person grows the group; swipe a card left to remove. A card swiped part-way open waits five seconds for a tap and then springs shut on its own, unless the keyboard is inside it. Dragging one slider sets that row only; everyone else stays put. Saving is refused only when requested shares exceed the bill. |
| Review (composer step 3) | Each person with their payment method and amount, You pay, Request split, Save split, a way back | Any valid draft | Both actions submit the draft. Nothing is written before this. |
| Send requests (split detail) | Bill title, total and people count; a request per unpaid person; Share requests; paid people below; the organizer's own payment details; the split link; Edit | Nothing paid; partly paid; fully paid ("All settled") | Each request is a text with a pay link. Share requests copies the group message and shows a Shared! recap with Close. |
| Share page (friend view) | Split title, total, each person and their amount, an "I paid" action on each unpaid row | Nobody paid; some paid; all paid; link not found | Tapping "I paid" asks to confirm the name, then marks it. No login. |
| History | Each split's title, date, total, and amount still owed | Empty; a few splits; many | Tapping a split opens its detail. |

Editing a saved split reopens the composer on the People step with the saved rows; it is not a
separate screen. Searching and creating contacts happens in the Connect sheet on each person.

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
3. **Custom split.** Setting someone's amount sets that row and holds it. Everyone else keeps
   what they already have — nothing is re-evened out from under the organizer — so money freed
   up by lowering one row is theirs to hand out. **Split evenly** gives every row an equal
   share of the whole bill, using rule 2, and frees them all. A saved split is custom exactly
   when at least one row is held; the hold is stored but nothing in the UI shows it.

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
6. **Limits.** A draft starts with 0 people; saved splits have 1 to 20 people, and every one of them is connected. The total is at least 1 cent per person and at most $99,999.99.
   No negative amounts.

   On a rejected total reduction, the sliders temporarily share a range large enough to display the existing amounts unchanged. The over-bill state blocks saving until corrected.

Currency is assumed to be US dollars for v1.

## Data model

Three tables in SQLite. A `Split` has many `Participants`; each participant may point to a
saved `Person`, or stay an unnamed placeholder.

| Table | Columns | Validations and notes |
| --- | --- | --- |
| splits | `title` (string), `total_cents` (integer), `split_mode` (even or custom), `share_token` (string, unique), `owner_token` (string), timestamps | Title required, 80 characters max. Total above 0 and at most 9,999,999. Participants add up to the total. `has_secure_token :share_token` makes the link hard to guess. |
| participants | `split_id`, `person_id` (optional), `position` (integer), `amount_cents` (integer), `payment_method` (venmo, cash_app or cash), `locked` (boolean), `paid_at` (datetime, empty until paid), timestamps | 1 to 20 per saved split. Amount 0 or more. `position` sets list order and who gets the leftover cent. A placeholder shows "Person 3" from its position. |
| people | `name` (string), `phone_number` (E.164, optional), payment handles, `owner_token` (string), timestamps | Name required, 40 characters max, unique per owner. Searched by name for the people picker. |

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
| Shares update as you type, add and remove people, connect, review | Stimulus only (`QuickSplitLogic`, `SplitFlowLogic`) | none | none |
| Save a split or request it | Turbo Drive, then redirect to requests | `POST /splits` | `SplitsController#create` (via `SplitDraft`) |
| Edit a saved split | The same composer, submitted again | `GET /splits/:id/edit`, `PATCH /splits/:id` | `SplitsController#edit`, `#update` (via `SplitDraft`) |
| Search saved people | Stimulus debounce, JSON | `GET /people/search?query=ma` | `PeopleController#search` |
| Change a friend's phone number | Turbo Frame in the request row | `GET/PATCH /people/:id` | `PeopleController#edit`, `#update` |
| Open the share link | Turbo Drive page, no login | `GET /s/:share_token` | `SharesController#show` |
| Friend taps "I paid" | Turbo Stream: replace that row | `POST /s/:share_token/participants/:id/payment` | `PaymentsController#create` |
| History | Turbo Drive page | `GET /splits` | `SplitsController#index` |

```ruby
Rails.application.routes.draw do
  root "splits#new"                         # the quick split
  resources :splits, only: %i[index create show edit update] do
    resources :participants, only: %i[create update destroy]  # old row editor; no screen uses it now
  end
  resources :people, only: %i[index create show edit update] do
    get :search, on: :collection                              # the Connect sheet's search
  end
  resource :payment_profile, only: %i[show edit update]      # how the organizer gets paid

  # Public share link
  get "s/:share_token", to: "shares#show", as: :share
  post "s/:share_token/participants/:participant_id/payment",
       to: "payments#create", as: :share_payment
end
```

`SplitsController#create` and `#update` both go through `SplitDraft`: the browser posts every
row (person, payment method, amount, held or not, and the participant id when it already
exists), and the server rebuilds the rows, redoes even shares with `SplitMath`, and refuses a
split that exceeds its total or has an unconnected person. A row's id is used only to remember
who has already paid; an id from another split is ignored.

## Asking for the money

*Added 2026-11-05.*

Splitting the bill is half the job; collecting it is the other half. Both directions are
supported: the organizer asking each friend, and a friend paying the organizer.

| App | Request (organizer → friend) | Pay (friend → organizer) |
| --- | --- | --- |
| Venmo | A text containing a Venmo link that opens ready to pay the organizer. | Real link, `https://venmo.com/<user>?txn=pay&amount=&note=`. |
| Cash App | A text containing a Cash App link that opens ready to pay the organizer. | Real link, `https://cash.app/$<cashtag>/<amount>`. |
| Cash | "Paying in cash". Nothing is sent. | Nothing to open; the friend confirms on the share page. |

*Revised 2026-11-05: Zelle and Apple Pay were dropped (no public link format, no merchant
account), and the "demonstration" panels below went with them. The paragraph below is kept as
the reasoning for why nothing fake is shown.*

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
- `Split`: invalid when participants exceed the total, or with fewer than 1 or more than 20
  people.
- `Split`: a share token is created on save.
- Creating a split from the quick split form redirects to requests.
- Saving a draft with an unconnected person is refused and writes nothing.
- Editing a saved split replaces its rows, keeps who has paid, and ignores a row id that belongs
  to another split.
- The share page loads by token; a wrong token returns 404.
- "I paid" sets `paid_at` on that participant only.
- A browser with a different owner cookie can't edit someone else's split.

## Build order

The design chat needs the Quick split and Split editor screens before step 3. The rest can
follow while the build runs.

1. New Rails 8 app with SQLite and Tailwind, pushed to GitHub.
2. Migrations, models, `SplitMath`, and their tests.
3. Quick split screen.
4. Save a split and edit it.
5. Connecting people: search, create, recent friends.
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
are visible. It identifies the person and chooses Venmo, Cash App, or cash; it does
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
- Payment choices use locally stored Venmo and Cash App logos and a cash icon.
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

Saving a draft opens **Send requests**. A compact bill title, total, and people
count precede the unpaid request cards; each card leads with the name, amount, and chosen
payment action. Paid rows sit below the requests. Edit is a filled toolbar action that reopens
the composer on the People step.

The shared message contains outstanding amounts and the public split link, not organizer
charge links. **Share requests** copies that message and shows a **Shared!** recap (total,
people requested, still owed, what you pay, and each person's amount) with a Close link home;
it does not open a device share sheet and does not claim anything was sent. Cash remains
an arrangement until the friend confirms on the share page.

*Revised 2026-11-05: Zelle, Apple Pay and "Save and view requests" no longer exist, and the
device share sheet was replaced by the copy-and-recap flow above.*

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
card. **Next** sits below You pay and stays disabled until every person is connected (cash
counts) and the shares do not exceed the bill. Swipe removal, sliders, and each person's keypad
and Connect drawer retain their behavior.

*Revised 2026-11-05: Request split no longer appears on the People step. It moved to Review.*


### Review, editing and Shared — November 5, 2026

**Next** opens a **Review** step on the same page: each person with their payment method and
amount, **You pay**, and two actions, **Request split** and **Save split**. A back arrow returns
to the people. Both actions submit the draft; Review is the only place either lives, so there is
one last look before anything is written down. Everyone must be connected to reach it, and the
server refuses an unconnected person too.

Editing a saved split renders this same composer, already on the People step, with the saved
rows as the draft. Changing the total there keeps the rows as they are (they are custom), so a
lower total shows "Over the bill by" until the organizer taps **Split evenly**. Saving replaces
the rows and keeps who has already paid.

Share requests ends on a **Shared!** recap with Close (see above). Close goes home.
