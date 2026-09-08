# Architecture

How the project is put together, and why it is shaped this way.

## The core idea: rules are not allowed to know about the screen

The single most important decision here is that the game **simulation** and the
game **presentation** are separate, and the dependency only points one way:

```
        Scripts/Core                    Scripts/UI + Scripts/Systems
   +---------------------+           +-----------------------------+
   |  GameRules          |  events   |  EventPresenter             |
   |  Deck               | --------> |  CardView / HudLayer        |
   |  CardData/CardTypes |           |  EffectsDirector            |
   |  AIPlayer           |           |  AudioDirector              |
   +---------------------+           +-----------------------------+
     no Node, no Texture,              may read rules state,
     no yield, no tween                may never mutate it
```

`Scripts/Core` extends `Reference` and imports nothing from the engine's scene
tree. That has three concrete payoffs:

1. **The rules are testable without a window.** `Tests/TestRules.gd` plays 100
   seeded games in about a second, on a machine with no GPU.
2. **State is final before any animation starts.** `play_card()` returns with
   the hand, the pile, the turn pointer and the score already updated. A tween
   can be slow, be sped up by the accessibility slider, or be skipped entirely,
   and the simulation cannot drift out of sync with it.
3. **Games are reproducible.** Every `Deck` and `AIPlayer` takes a seed, so a
   bug report can be replayed exactly.

The original code had none of this: `GameManager.gd` was a 1245-line node that
mutated arrays in the middle of `yield`-ing animation coroutines, which is the
root cause of most of the bugs listed in `docs/PRODUCTION_NOTES.md`.

## The event queue

`GameRules` never calls the UI. It appends to an internal queue, and the caller
drains it:

```gdscript
rules.play_card(0, card, chosen_color)
presenter.process_events(rules.consume_events())
```

Each event is a small dictionary with a type and a payload:

```gdscript
{ "type": Event.CARD_PLAYED, "player": 0, "card": <CardData>, "top": <CardData> }
```

The full set is `GAME_STARTED`, `CARD_DEALT`, `OPENING_CARD`, `CARD_PLAYED`,
`CARD_DRAWN`, `COLOR_CHOSEN`, `COLOR_CHOICE_REQUIRED`, `TURN_CHANGED`,
`DIRECTION_REVERSED`, `PLAYER_SKIPPED`, `PENALTY_DRAW`, `STACK_GROWN`,
`UNO_CALLED`, `UNO_PENALTY`, `HANDS_SWAPPED`, `HANDS_ROTATED`, `DECK_RECYCLED`,
`DECK_EXHAUSTED`, `ROUND_ENDED`, `MATCH_ENDED` and `INVALID_MOVE`.
Events carry everything the presentation needs inline — `CARD_PLAYED` includes
the player, the card, the remaining hand size and a `jump_in` flag for
out-of-turn plays.

This is what makes the presentation layer replaceable. A text-only front end, a
replay viewer, or a network client would consume the same queue.

## Layers

### `Scripts/Core` — the simulation

| File | Responsibility |
| --- | --- |
| `CardTypes.gd` | Colour/value enums, asset keys, scoring constants, accessibility glyphs. |
| `CardData.gd` | One card. Immutable apart from `chosen_color`. Carries a unique `uid`. |
| `Deck.gd` | Builds the 108-card deck, seeded shuffle, draw/discard, recycling. |
| `GameRules.gd` | The state machine: turns, direction, stacking, penalties, scoring, the event queue. |
| `AIPlayer.gd` | Opponent decisions. Three difficulties, tracks which colours each seat is void in. |

`GameRules.Ruleset` is a small inner class holding the house rules
(`stacking`, `draw_until_playable`, `seven_zero`, `jump_in`, `force_play`,
`target_score`, `starting_hand`) so a match's configuration travels as one
object.

### `Scripts/Systems` — engine-facing services

| File | Responsibility |
| --- | --- |
| `SettingsManager.gd` | `user://settings.cfg`, versioned, with migration. Emits `settings_changed`. |
| `AudioDirector.gd` | Synthesises every sound effect at boot into `AudioStreamSample`. Voice pool + music bus. |
| `ThemeFactory.gd` | Fonts, colour tokens and `StyleBox`es. One place to restyle the whole UI. |
| `EffectsDirector.gd` | Pooled particles, floating text, screen shake, flashes, the table vignette. |
| `ReactionDirector.gd` | Delayed opponent reactions: UNO-catch windows and AI jump-ins. See below. |

### `Scripts/UI` — presentation

| File | Responsibility |
| --- | --- |
| `TableLayout.gd` | **All** on-screen geometry. Pure static functions. See below. |
| `EventPresenter.gd` | Translates the event queue into animation, sound and HUD calls. |
| `CardView.gd` | One card on screen: shadow, glow, face, hover/drag, flip, fly-out. |
| `HudLayer.gd` | Status pill, counters, scoreboard, seat plates, action buttons. |
| `MenuLayer.gd` | Main/pause/settings/help/stats/round/match screens. |
| `ColorPicker.gd` | The wild-card colour overlay. |

### `Scripts/GameController.gd` — the orchestrator

Owns the scene, the systems and the input handling; drives the turn loop. It is
the only script that both reads rules state and touches nodes, which is exactly
why the event handling was moved out into `EventPresenter` — the controller was
otherwise heading past 1300 lines.

## Delayed reactions: ReactionDirector

Some opponent behaviour must happen *later*, on a real timer, for the game to
feel fair and alive:

- **UNO catch windows.** When a seat drops to one card without calling, an
  opponent arms a catch that fires after `AIPlayer.catch_delay()` (≈1 s on Hard
  to ≈2.2 s on Easy, scaled by the animation-speed setting). Until it fires,
  the player can still self-call — that window *is* the feature. The AI that
  catches is the next opponent in turn order after the victim, and AIs that
  forget their own UNO call are caught by the other CPUs too.
- **AI jump-ins.** Under the jump-in house rule, after any play an opponent
  holding an exact twin of the new top card may arm a jump-in that fires after
  a human-scale reaction delay. While the *human* is the one deciding, nothing
  is armed — opponents react to plays, never to hesitation, so a fast click
  always wins.

`ReactionDirector` follows the same shape as `EventPresenter`: a `Reference`
with a back-reference to the controller, no scene nodes of its own. Reactions
are **armed** when `evaluate()` (called after every event batch) finds them
possible, and **re-validated** when they fire — the state may have changed in
between (self-call, another card on top, round over). Tokens invalidate
everything armed by an older table when the round restarts.

All gameplay timers are created with `process_always = false`, so a pause menu
freezes the deal, the AI's think time and every armed reaction. Cosmetic-only
timers would keep running, which is why the distinction is deliberate.

## Layout is computed, not hand-placed

`TableLayout.gd` is the single source of truth for where everything sits. It
divides the screen into horizontal bands and solves for them:

```
  top HUD      status pill / deck counts / scoreboard
  opponent fan(s)
  opponent name plates
  play row     draw pile + discard + colour chip + direction
  player fan   your hand
                                    action buttons: right-hand column
```

Band heights derive from the **rotated** bounding box of a card, not the
upright one — the outer cards of a fan are tilted, and using the naive
axis-aligned size is what pushed the player's hand off the bottom of the screen.
Leftover vertical space is shared out as even gaps, and everything scales by a
single `scale_factor()` (clamped to 0.58–1.32 of the 1280×720 reference).

Because the geometry is pure functions of the viewport size, it can be tested
without rendering. `Tests/TestLayout.gd` asserts across seven resolutions and
seven hand sizes that no two regions overlap, nothing leaves the viewport, and
no HUD string overflows its panel.

The buttons run **down the right edge** rather than across the middle. The
original horizontal bar sat at y=448 and collided with both the discard row and
the player's hand at the default resolution.

## Depth is banded, not incidental

`DrawOrder.gd` is the single source of truth for what draws on top of what —
the vertical counterpart to `TableLayout`. Two axes matter:

1. **CanvasLayers** separate the big strata: the world renders in the implicit
   layer 0, then the HUD (5), the colour flash (8), the colour picker (15) and
   the menus (20). No card can ever render above the HUD, and no menu renders
   under the picker it may be answering.
2. **z_index bands** order the world. Godot sorts every canvas item in a layer
   by effective z (a child's z adds to its parent's) and breaks ties in *tree*
   order — i.e. by spawn order, which is not the order things happened in.
   Relying on those tie-breaks is how the game shipped with a discard pile that
   painted in deal order instead of play order.

Each group therefore owns a band that no other group can reach:

```
  z    0      table felt
  z   10-14   deck stack (the five face-down backs)
  z   20-26   discard pile (bottom .. top, re-stamped on every play)
  z   60-199  resting hand cards (index within the hand, any seat)
  z  220      cards in transit - dealt, drawn, played, leaving
  z  240      the hovered card, lifted out of its fan
  z  280      the dragged card
  z  320+     particle bursts and floating text
```

A hand can never hold more cards than the deck contains, so the hand band
cannot reach the flight band; the clamps in `DrawOrder.hand()` make that
explicit. Cards *in transit* fly in the flight band above everything at rest
and settle into their resting band only when the flight lands (`CardView`
tracks this as `_in_flight`), so a thrown card clears even a 20-card fan on
its way to the pile, and a dealt card slides off the *top* of the deck rather
than out from underneath it.

`Tests/TestDrawOrder.gd` recomputes the paint order exactly the way
`VisualServerCanvas` does (accumulate z down the tree, sort by z, ties in tree
order) and asserts the band contract across the deal, mid-flight plays, hover,
drag and pathological hand sizes.

## Animation

Godot 3.5's `SceneTreeTween` (via `create_tween()`) is used throughout — no
`Tween` nodes are allocated per card. `CardView` keeps one tracked tween per
purpose (`_move_tween`, `_hover_tween`, `_pulse_tween`) and kills the previous
one before starting a new one, so a card cannot be driven by two conflicting
animations.

Every duration passes through `SettingsManager.anim_scale()`, so the animation
speed setting uniformly affects card movement, AI thinking time and the delay
before summary screens.

## Audio

No audio files ship with the project. `AudioDirector` renders 16-bit mono PCM
into a `PoolByteArray` at boot and wraps it in an `AudioStreamSample`: shuffles,
deals, plays, draws, penalties, UNO calls, wins and a looping music bed. It
keeps the repository free of binary assets while still shipping a full sound
bed, and every cue is a few lines of code to retune.

## Safety nets

Two failures were found by running the game rather than reading it, and both
now have permanent guards:

- **Rules deadlock.** With an exhausted, unrecyclable shoe, a player could
  neither draw nor pass. `can_pass()` now permits passing in that state,
  `draw_for_turn()` ends the turn rather than stranding it, and `_is_stalemate()`
  closes the round in favour of the lowest hand.
- **Dropped AI turn.** A scheduled opponent turn whose timer was invalidated
  used to leave `_busy` stuck true with nothing queued. Stale turns now hand
  control back to the dispatcher, and `_process()` runs a watchdog that
  re-dispatches after six seconds.

## Testing

| Suite | Scope | Runtime |
| --- | --- | --- |
| `Tests/TestRules.gd` | Rules engine, AI legality, jump-in semantics, 100-game soak, card conservation. | ~1 s |
| `Tests/TestLayout.gd` | Geometry across 7 resolutions, text fit, font glyph coverage. | ~1 s |
| `Tests/TestDrawOrder.gd` | Canvas strata, z bands, pile play order, flights, hover and drag depth, interrupted-flight healing. | ~20 s |
| `Tests/TestIntegration.gd` | Boots the real scene: menus, settings, full matches, human and AI jump-ins, the catch window, resizes, teardown. | ~35 s |

```bash
godot --no-window -s Tests/TestRules.gd
godot --no-window -s Tests/TestLayout.gd
godot --no-window -s Tests/TestDrawOrder.gd
godot --no-window -s Tests/TestIntegration.gd
```

All four exit non-zero on failure and run in `.github/workflows/ci.yml`.
See [TESTING.md](TESTING.md) for a guide to the suites and how to extend them.

`Tests/DumpLayout.gd` is a diagnostic rather than a test: it writes the resolved
geometry to `user://layout_dump.json`, which `Tools/preview_layout.py` renders
into a PNG mock-up using the real card art. That is how the layout was reviewed
without a GPU, and it caught clipping and collisions the numeric assertions had
missed.

`Tests/HangProbe.gd` is the gameplay equivalent: a soak probe that boots the
real game and plays it like a person — hovering, clicking, dragging,
misclicking unplayable cards — across opponent counts, animation speeds and
house rules, watching for wedged turn flow, dead input flags and hand cards
that end up off-slot, invisible or stuck mid-flight. It found the ghost-card
hangs described in the production notes; it is run manually, not in CI.

## Conventions

- Tabs for indentation; two blank lines between top-level definitions.
- `_leading_underscore` for private members.
- `gdlint` is the gate (see `gdlintrc`); `gdformat` is deliberately not used
  because it collapses tween chains past any workable line limit.
- Comments explain *why*, not *what*.
