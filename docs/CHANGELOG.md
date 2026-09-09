# Changelog

All notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
version lives in `project.godot` (`application/config/version`).

## [1.2.0] — 2026-09-08

### Added

- **Android TV / Fire TV support.** The whole game is playable with nothing
  but a remote's D-pad, Select and Back — no touch, no mouse, no hotkeys.
  During a hand, Up jumps between your cards and the action buttons (the
  selected button wears a glowing accent strip); Enter activates it; Back
  pauses. When nothing is playable the selection starts on DRAW. Menus and
  the colour picker already spoke the engine's focus system, which the remote
  drives natively. All routing lives in a new `InputRouter` system, shared by
  keyboard and gamepad.
- **Named, avatar'd opponents.** Each match seeds a table from a roster
  (Hugo the owl, Kira the robot, Bruno the cat…) with generated portrait art
  on the seat plates. The seed matches the deck, so a match always fields the
  same table.
- **A real turn-direction indicator**: a coloured ring spinning around the
  discard pile in the direction play actually passes, pulsing on every
  hand-off and flipping on a Reverse. The old guilmet in the status bar
  stays as a secondary marker.
- Juice: cards squash on landing on the pile, the active seat plate pops when
  it takes the turn, and pile throws carry a slightly bolder hand-stacked
  rotation.

### Fixed

- **The center pile mixed card sizes**: a card played onto the pile kept the
  scale of the hand it came from, so your discards landed bigger than the
  CPU's (and vice versa). Every discard now re-bases to one pile scale, with a
  random tilt and offset so the pile reads as hand-stacked.
- **Jump-ins were unreachable through real input**: while an opponent was
  "thinking" — the only window a jump-in exists — all input was gated off, so
  the feature could never fire from a real click or keypress. Interaction is
  now live while busy whenever a legal twin is in your hand.
- Removed the five `game_*` input actions from project.godot: nothing read
  them (the router reads raw keys/pads), so editing those bindings silently
  did nothing.

### Changed

- Version 1.2.0; the README table preview was re-rendered through the layout
  pipeline with the new ring, avatars and seat plates.
- Test bed grows to 3208 assertions: turn-ring geometry in `TestLayout`, and
  an opponents/pile/remote group in `TestIntegration` (named seats, avatars,
  uniform pile scale, varied rotation, ring direction, the D-pad zone dance,
  drawing via the focused button).

## [1.1.0] — 2026-09-08

### Added

- **Jump-in house rule** (off by default): a card identical to the top of the
  discard pile — same colour and value — can be played out of turn by anyone.
  The twin stays highlighted in your hand while another seat decides, and
  opponents jump in on a human-scale reaction delay, so a fast click always
  beats them. Wilds, the untouched opening card and live draw stacks are
  exempt. The rules engine, AI, HUD, input layer, help text and docs all
  support it, with dedicated rules and integration tests.
- **UNO catch windows**: a missed UNO call is now punished after a fair,
  difficulty-scaled delay (`catch_delay()` existed but was never wired up)
  instead of instantly at the start of the opponent's turn. The window is
  exactly the time you have to self-call with **UNO!** — and the button now
  works during it (previously it was disabled off-turn even though the call
  was legal).
- **AI-vs-AI catches**: opponents who forget their own UNO call (Easy ones
  especially) can now be caught by the other CPUs, not only by you.
- **Rounds played / round win rate** career stats, shown on the statistics
  screen alongside the match stats.
- Round summary now shows the per-round point breakdown (`+37`) next to each
  player's running total.
- A version label on the main menu, sourced from `project.godot`.
- A table vignette, a reversal flourish on the direction indicator, a
  low-deck warning tint on the deck counter, and a celebratory spin + sparkle
  on the winning card.
- `docs/TESTING.md` (a guide to the four suites and how to extend them) and
  this changelog.

### Fixed

- **Pausing no longer lets the game play on.** Gameplay timers (AI think time,
  the deal, the opening reveal, summary delays, armed reactions) were
  `SceneTreeTimer`s with `process_always = true`; opening the pause menu
  mid-think let the AI take its turn — state, sound and all — while the screen
  was frozen. All gameplay timers now pause with the tree.
- **The high-contrast toggle did nothing** after boot: the theme was built once
  in `_ready()` and never rebuilt. It is now regenerated and re-applied to the
  HUD, menu and picker roots live.
- **The UNO button was disabled during the late call** (see catch windows
  above), making the keyboard work but the button not.
- **The CATCH button could go stale**: it was only re-evaluated at the start of
  your turn, so it could point at a player who had already drawn or self-called
  — and a failed catch click did nothing, silently. It is now recomputed from
  live rules state on every refresh, and a failed catch says so.
- **Window resize flattened the discard pile**: every resting discard snapped
  to the exact pile centre, losing the hand-stacked jitter. Each view now
  remembers its offset.
- **Untracked glow fade could fight a fresh pulse**: an in-flight fade-out
  tween landed its final alpha on top of a newly started playable-glow pulse.
  The fade is now tracked and killed like every other per-purpose tween.
- **A racy assertion in the draw-order suite** (found by running): the
  pile-order check sampled the top discard's depth while an opponent's card,
  played late in the turn window, was still in the flight band — by design a
  card in transit paints at z 220. The suite now waits for pile flights to
  land before sampling, and eight consecutive runs are clean.
- Removed dead code: `AudioDirector.play_sequence` (never called),
  `EffectsDirector._vignette` (declared, never built — now it is the vignette)
  and a confusing double guard in `CardView.flip_to`.

### Changed

- `ReactionDirector.gd` extracted from `GameController` (which was brushing the
  1200-line lint cap): delayed opponent reactions now live in their own file,
  mirroring the `EventPresenter` pattern.
- Opponent plays now flip with a card-flip cue, multi-card draws rise in pitch
  card by card, and Draw Two plays get their own thud.
- Screen shake decay is frame-rate independent (exponential per unit time
  instead of a per-frame lerp).

### Performance

- `CardView.move_to()` no-ops when a card is already parked at exactly its
  rest pose: the refresh after every event batch used to restart a 0.34 s
  tween per resting card, forever.
- `EffectsDirector.float_text()` caches its fonts by size instead of building
  a fresh filtered `DynamicFont` per call.

## [1.0.0] — 2026-09-08

The first production pass over the original prototype.

- Split the 1245-line `GameManager.gd` monolith into a pure rules engine
  (`Scripts/Core`) plus presentation layers, connected by a semantic event
  queue.
- Computed layout and paint order in single sources of truth
  (`TableLayout`, `DrawOrder`) instead of hand-tuned margins and incidental
  z-fighting.
- Synthesised the entire sound bed at runtime; no binary audio in the repo.
- Accessibility: animation-speed scaling, colour-blind markers, high contrast,
  screen-shake and particle toggles, full keyboard/gamepad navigation.
- Four headless test suites (3121 assertions) wired into CI, plus the layout
  dump / preview pipeline and the HangProbe soak.
- Repository slimmed from 31 MB to 8.4 MB (dropped the stale committed build
  and unused font weights).
- Full bug history for this pass: [PRODUCTION_NOTES.md](PRODUCTION_NOTES.md).
