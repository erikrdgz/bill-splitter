# Bill Splitter

Read SPEC.md first. It is the product and build plan.

## Why this app exists

I'm a designer and front-end developer learning Rails 8 and Hotwire, the stack Decile Group uses.
This app is how I'm learning it: a real product with a real database, built to the standard I'd
hold any production code to.

The stack: Rails 8, Turbo, Stimulus, Tailwind, Hotwire with ERB. Postgres in production; SQLite is
fine here. The kind of work I want it to show: polished UI, workflow-heavy interfaces (forms,
lists, money), working comfortably in a Rails codebase, and using AI tools daily.

How I want the code built:
- Code I'd be proud to take credit for. Quality over speed.
- Each step is a complete change: a model, a migration when needed, and the tests that go with it.
- Ownership: if a design is missing, mock it; if a product decision is missing, make it and note it.
- Small, shippable steps. Leave code cleaner than you found it.

## How to work with me

- I'm new to Rails. I must be able to explain every file in a 30-minute walkthrough.
  Before each step, say in one or two lines what we're building and which Rails/Hotwire idea it shows.
- Keep it idiomatic Rails. Skinny controllers, logic in models. No React-style patterns.
- Server renders HTML. Stimulus only where the browser must react before the server can.
- Add short comments that explain WHY, not what.
- Keep a DECISIONS.md: one entry per meaningful choice (e.g. why GET vs PATCH, why a Turbo Frame vs a Stream,
  why money is integer cents). I should be able to defend every entry out loud.

## Naming

- View partials are named for what they show: ParticipantRow -> _participant_row.html.erb
- Stimulus controllers use a Logic suffix: SplitLogic -> split_logic_controller.js
- Active Record models keep Rails names (Split, Participant, Person). Plain Ruby rules without a table get
  a descriptive name (SplitMath).
- Variables and methods: full, descriptive names. No abbreviations like amt, ppl, idx.

## UI for now

Black and white only, plain and readable. A full visual redesign comes later from a separate design pass,
so keep markup semantic and styling in Tailwind classes that are easy to replace.
No status chips, pills, or badges.

## Tests

Minitest (Rails default). Write tests alongside each step, not at the end. Run the suite before every commit.

## Git

- Commit after each working step with a plain message describing the change.
- Push to GitHub after each commit.
- No Claude, AI, or co-author attribution lines in commit messages.

## My machine

macOS, Apple Silicon, Homebrew Ruby 4.0. If gem installs fail with a permission error under
/opt/homebrew/lib/ruby, install gems to a user directory (GEM_HOME) instead of using sudo.
