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
| `EffectsDirector.gd` | Pooled particles, floating text, screen shake, flashes. |

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
| `Tests/TestRules.gd` | Rules engine, AI legality, 100-game soak, card conservation. | ~1 s |
| `Tests/TestLayout.gd` | Geometry across 7 resolutions, text fit, font glyph coverage. | ~1 s |
| `Tests/TestIntegration.gd` | Boots the real scene: menus, settings, full matches, resizes, teardown. | ~30 s |

```bash
godot --no-window -s Tests/TestRules.gd
godot --no-window -s Tests/TestLayout.gd
godot --no-window -s Tests/TestIntegration.gd
```

All three exit non-zero on failure and run in `.github/workflows/ci.yml`.

`Tests/DumpLayout.gd` is a diagnostic rather than a test: it writes the resolved
geometry to `user://layout_dump.json`, which `Tools/preview_layout.py` renders
into a PNG mock-up using the real card art. That is how the layout was reviewed
without a GPU, and it caught clipping and collisions the numeric assertions had
missed.

## Conventions

- Tabs for indentation; two blank lines between top-level definitions.
- `_leading_underscore` for private members.
- `gdlint` is the gate (see `gdlintrc`); `gdformat` is deliberately not used
  because it collapses tween chains past any workable line limit.
- Comments explain *why*, not *what*.
