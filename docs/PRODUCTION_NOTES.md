# Production Notes

The state of the project, what was fixed and why, and what is still open.

## Bugs found and fixed

Each of these was a real defect in the shipped code. The ones marked **found by
running** were not visible by reading the source — they surfaced from the
headless test suites or the layout preview renderer.

### Rules and state

| Bug | Detail |
| --- | --- |
| Card loss on reshuffle | `reshuffle_discard_into_deck()` used `slice(0, size - 2)`. Godot's `Array.slice()` is **inclusive** on the upper bound, so the arithmetic silently dropped a card each recycle. `CenterCards[size - 1]` was also read unchecked. |
| **Softlock on an exhausted deck** (found by running) | With the draw pile empty and only the face-up card in the discard, `can_draw()` stayed true, drawing produced nothing, and `can_pass()` stayed false. The turn could never end. Now `can_pass()` allows passing in that state, `draw_for_turn()` ends the turn instead of stranding it, and a stalemate check closes the round in favour of the lowest hand. Covered by two regression tests. |
| **Dropped AI turn** (found by running) | If a scheduled opponent turn was invalidated (restart, menu, rebuild) the handler returned early leaving `_busy` stuck true with nothing queued — the game froze. Stale turns now return control to the dispatcher, plus a six-second watchdog in `_process()` as a backstop. Reproduced roughly 1 run in 8 before the fix; 14 consecutive clean runs after. |
| Status message clobbered | `complete_turn()` overwrote the Skip/Reverse/Draw message with a generic turn message. |
| Unfair UNO penalties | `resolve_uno_call()` penalised the wrong player in some orders, and drawing reset `player_called_uno`, silently cancelling a valid call. |
| Input race | `AI_Turn()` was called without handling its `yield`, and `busy` was cleared before `PlayCard()` finished, letting the player act mid-animation. |
| Opening card loop | `draw_starting_discard()` re-inserted and reshuffled up to 80 times to avoid starting on a wild. |

### Presentation

| Bug | Detail |
| --- | --- |
| **Missing font glyphs** (found by running) | The colour-blind markers (`▲ ● ■ ♦ ★`) and the turn-direction arrows (`↻ ↺`) do not exist in any bundled Roboto weight — they rendered as empty tofu boxes, so the accessibility feature actively did not work. Replaced with letters and guillemets. `Tests/TestLayout.gd` now measures every UI glyph against the notdef advance so this cannot regress. |
| **Layout collisions** (found by running) | At the default 1280×720 the opponent seat plate sat at y=−66 (off-screen), the player plate at y=696 overlapped the hand, and the horizontal button bar at y=448 crossed both the discard row and the player's fan. |
| **Hand clipped off-screen** (found by running) | Fan bounds were computed from the upright card size. The outer cards of a fan are rotated, so the real bounding box is ~25 px taller per card and the hand ran off the bottom edge. |
| **Scoreboard overflow** (found by running) | At 800×480 the `ROUND n - FIRST TO 500` header rendered wider than its panel and ran off the right edge. It now abbreviates, and a test asserts every HUD string fits its rectangle. |
| Resize handled one node | `_on_viewport_size_changed()` repositioned only the top centre card. |
| Card view defects | Hover scaling restored on non-playable cards; `set_interaction_enabled(false)` called `stop_all()` and could strand a card mid-flight; stale `home_position` after a resize; a permanent `raise()` broke fan z-order; the face texture was assigned while the card was still face-down, leaking a one-frame reveal. |
| **The discard pile painted in deal order** (found by running) | Hand cards and the pile shared the z range 0..29, and every discard past the sixth landed on the same z (10 + pile size, with the pile capped at six). Godot breaks z ties in tree order — spawn order — so a freshly played card slid *under* the card it was supposed to cover. Each group now owns a `DrawOrder` z band, and the pile is re-stamped bottom-to-top on every play. |
| **Cards in transit drew under the table furniture** (found by running) | A card dealt from the deck flew with its final hand index (z 0..6), i.e. *under* the deck backs (z 1..4), and a card thrown at the pile (z ~10-16) flew under every hand card past index ten. Dealt, drawn and played cards now fly in a dedicated band above everything at rest and settle into their band only on landing. |
| **The staggered deal never played** (found by running) | `deal_from()` built a delayed, staggered flight, then the `_refresh_all()` at the end of the event batch called `move_to()` on every card, killing each deal tween before a frame rendered — all cards left the deck simultaneously. Dealt cards now fly straight to their fan slot and the layout recognises an in-flight card already heading there. |
| **A refresh stomped the hovered card's depth** (found by running) | Any event-batch refresh reset a hovered card's z to its resting depth while it was still lifted, dropping it under its neighbours until the mouse moved again. `move_to()` now defers to the hover (and drag) state. |
| **Invalid native icon on Windows** | `config/windows_native_icon` pointed at `icon.png`; the Windows loader expects a real `.ico`, and boot failed its `idType != 1` check on the PNG header. Shipped a proper DIB-encoded `icon.ico` (16–64 px, 32 bpp) generated from the same artwork. |
| Editor script warnings | Two unused locals (`TableLayout.metrics()`, `AudioDirector._make_card_draw()`) and six HUD signals emitted through a variable — `emit_signal(signal_name)` — which the 3.5 parser cannot see, so it reported them as never emitted. Buttons now dispatch through a `match` that emits each signal by literal, and the dead `_on_button_hover` stub (GameController already plays the hover cue on those buttons) is gone. |
| **Ghost cards hung the game** (found by running) | Three paths could interrupt a card's deal flight and leave it stranded: a re-layout while the fan re-flowed killed the fade-in (a permanent near-invisible card), a rejection shake on a card still flying in left it stuck in the flight band above the fan — floating there and swallowing clicks meant for the cards beneath, which reads as "the game hangs" until a pause/resume (whose refresh, plus the mouse crossing the cards afterwards, re-lays the hand) — and `move_to()` kept deferring to flight tweens that were already dead, because `SceneTreeTween.kill()` does not clear `is_valid()`. Every interruption now lands the card: re-targets finish an interrupted fade, the shake restores pose/opacity/flight state, liveness is judged by `is_running()`, and `_settle()` guarantees a landed card is opaque. A soak probe (`Tests/HangProbe.gd`) drives the real input path — hovers, clicks, drags, misclicks, UNO-less play — across opponent/animation/rule configs and flags any hand card that is off-slot, invisible, transparent or stuck in flight. |
| Use-after-free | Culled discard views could still be reached by a pending click or timer. Guarded with `is_instance_valid()`. |

## Performance

| Change | Effect |
| --- | --- |
| `create_tween()` instead of `Tween.new()` + `add_child()` | The old code allocated and parented a node per card per reposition, play and pulse. `CardView` now keeps one tracked tween per purpose and kills the previous before starting a new one. |
| Pooled particles | Bursts allocated a `CPUParticles2D`, waited on a 1.0 s `yield`, then freed it. `EffectsDirector` pools ten emitters and eight floating labels. |
| HUD moved to a `CanvasLayer` | `update_ui()` called `raise()` on every update to keep the HUD on top. |
| SFX cached once | Samples were regenerated in GDScript at startup on every launch; now built once in `AudioDirector._build_streams()`. |
| Discard culling | Only the newest six discards stay in the scene tree. |

## Repository size

31 MB → 8.4 MB.

- Removed the committed `build/` directory (22 MB). It was a stale web export of
  the deleted monolith — the `.pck` still contained `GameManager.gd` and
  `Card.gd`. Shipping a build that does not match the source beside it is worse
  than shipping none. `build/` is now ignored and `export_presets.cfg` is
  committed so it can be regenerated reproducibly.
- Removed nine unused Roboto weights (kept Regular/Medium/Bold/Black).
- Removed `UnoAssets.pdf`, `Mockup.png` and `MockUp 0.png` (2.1 MB of design
  scratch). The five `Table_*.png` felts are used by the table setting and stay.

## Testing

3121 assertions across four headless suites, all wired into CI:

| Suite | Assertions | Scope |
| --- | --- | --- |
| `TestRules.gd` | 370 | Rules engine, AI legality, card conservation, 100-game seeded soak. |
| `TestLayout.gd` | 2644 | Geometry at 7 resolutions × 7 hand sizes, text fit, glyph coverage. |
| `TestDrawOrder.gd` | 51 | Canvas strata, z bands, the pile's play order, cards in transit, hover/drag depth, pathological hand sizes, interrupted-flight healing. |
| `TestIntegration.gd` | 56 | Boots the real scene: menus, settings, save/reload, full matches, 3- and 4-handed play, house rules, resizes, pause, teardown. |

Every suite exits non-zero on failure. Verified by deliberately introducing a
failure and confirming the exit code.

## Reviewing the UI without a GPU

The available Godot build is a headless server binary — video driver `Dummy`,
no `Xvfb`, no screenshot flag. Real screen captures are impossible.

Instead, `Tests/DumpLayout.gd` writes the resolved geometry (every card, plate,
button and HUD rectangle) to `user://layout_dump.json`, and
`Tools/preview_layout.py` composites that into a PNG using the actual card art:

```bash
godot --no-window -s Tests/DumpLayout.gd --width=1920 --height=1080 --opponents=3
python3 Tools/preview_layout.py --out /tmp/preview.png
```

This is a review aid, not a pixel-exact renderer — but it caught the clipped
hand, the plate/badge collisions and the scoreboard overflow, none of which the
numeric assertions had flagged. Every one of those became a test afterwards.

## Known limitations

- **The web build is not regenerated.** Exporting needs the Godot editor and
  export templates, neither of which is available here. `export_presets.cfg` is
  committed so `godot --export "HTML5" build/index.html` reproduces it in an
  environment that has them. The Pages deployment on the `WebBuild` branch is
  therefore still serving the old monolith until someone re-exports.
- **`gdformat` is not run.** Godot 3 GDScript cannot break a method chain, so
  the formatter collapses tween builders onto single lines it then cannot
  re-wrap, producing output that fails the project's own lint config. The source
  is hand-formatted to the same conventions and `gdlint` is the enforced gate.
  See the note in `gdlintrc`.
- **No multiplayer.** The event-queue design would suit it, but nothing is
  implemented.

## Suggested next steps

1. **Re-export the web build** from a machine with the editor, and point the
   Pages deployment at it. This is the highest-value remaining task.
2. **Replay files.** Deck and AI are already seeded; persisting the seed plus
   the action list would make bug reports exactly reproducible.
3. **Jump-in.** `Ruleset.jump_in` exists as a flag but is not implemented.
4. **Localisation.** All user-facing strings are inline; moving them to a
   translation table would be mechanical.
5. **Touch tuning.** Hit targets scale with the layout, but a dedicated phone
   portrait layout would need a new band arrangement in `TableLayout`.

## Manual QA checklist

Automated coverage handles most of this; these are the things worth a human eye.

- Sound: cues fire for deal, play, draw, penalty, UNO, win; music ducks under
  them; all three volume sliders take effect immediately.
- Feel: hover lift, drag tilt and the snap-back on an illegal drop.
- Particles and screen shake on Draw Four and on winning a round, and that
  disabling them in settings genuinely stops them.
- Colour-blind marks appear on both the HUD chip and the colour picker.
- High contrast and each of the five table felts.
- Resize the window mid-round and confirm the table re-lays out cleanly.
- Gamepad navigation through every menu screen.
