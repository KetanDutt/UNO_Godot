# Testing

How the project verifies itself, and how to extend it.

Everything runs headless — no GPU, no window, no X server — which is what makes
it practical to run the whole bed on every push.

## Quick start

```bash
godot --no-window -s Tests/TestRules.gd
godot --no-window -s Tests/TestLayout.gd
godot --no-window -s Tests/TestDrawOrder.gd
godot --no-window -s Tests/TestIntegration.gd
```

Each suite prints one line per assertion group and a final
`=== N passed, M failed ===`, then exits `0` on success and `1` on failure —
so they drop straight into CI (see `.github/workflows/ci.yml`).

If textures fail to load ("Make sure resources have been imported"), run the
editor once first:

```bash
godot --no-window --editor --quit || true
```

The suites pass without textures — they assert on state and geometry, never on
pixels — but booting with a full import exercises the real resource paths.

## The four suites

### TestRules.gd — the simulation (389 assertions, ~1 s)

Extends `SceneTree`, constructs `GameRules` directly, and never touches a scene.
Covers deck composition, seeded determinism, recycling, every card effect,
two-player Reverse, stacking, draw-until-playable, pass/draw legality, UNO
calls and catches, round/match scoring, seven-zero, force-play, jump-in
legality and turn flow, plus a 100-game seeded soak that asserts card
conservation and that every match terminates.

### TestLayout.gd — the geometry (2679 assertions, ~1 s)

`TableLayout` is pure functions of the viewport, so the suite can assert at
seven resolutions × seven hand sizes that bands never overlap, nothing leaves
the viewport, no HUD string overflows its panel, and every glyph the UI uses
exists in the bundled Roboto faces (the colour-blind markers once shipped as
tofu boxes — there is now a test that would have caught it).

### TestDrawOrder.gd — the paint order (51 assertions, ~15 s)

Boots the real scene and recomputes the effective z of every canvas item the
way `VisualServerCanvas` does (accumulate z down the tree, sort by z, ties in
tree order), then asserts the `DrawOrder` band contract: the pile paints in
play order, cards in transit fly above everything at rest, hover and drag lift
into their own bands, a 30-card hand cannot reach the flight band, and
interrupted flights heal (no ghost cards).

### TestIntegration.gd — the whole game (89 assertions, ~35 s)

Boots `Scenes/Gameplay.tscn` and drives it through the same entry points a
player uses: every menu screen, every settings toggle, a save/reload
round-trip, complete matches driven through `_try_play` / `_on_draw_pressed` /
`_on_pass_pressed`, three- and four-handed tables, house rules, window resizes
mid-round, pause/resume, jump-ins (human *and* AI), the UNO catch window,
opponent identities and avatars, the discard pile's uniform scale and rotation,
the turn-direction ring, the TV-remote selection model (zone switching, button
cycling, drawing via Enter on the focused button), and a clean teardown back
to the main menu.

## Diagnostics (not run in CI)

### DumpLayout.gd + Tools/preview_layout.py

```bash
godot --no-window -s Tests/DumpLayout.gd --width=1280 --height=720 --opponents=1
python3 Tools/preview_layout.py --out preview.png   # needs Pillow
```

Boots the game, plays a few turns, then writes the exact transform of every
card, plate, button and HUD rectangle to `user://layout_dump.json`. The Python
tool composites that into a PNG using the real card art. It is how the layout
was reviewed without a GPU — the `docs/images/table-preview.png` in the README
was produced this way.

### HangProbe.gd

```bash
timeout 900 godot --no-window -s Tests/HangProbe.gd -- --opponents=1 --anim=1.0 --rules=all
```

A soak probe that plays like a person through the real input path — hovers,
clicks, drags to the pile, misclicks unplayable cards — across opponent
counts, animation speeds and house-rule combinations, watching for wedged turn
flow, dead input flags, and hand cards that end up off-slot, invisible or
stuck mid-flight. It found the ghost-card hangs described in the production
notes. Expect `RESULT: hangs=0` at the end; the occasional "strand" line during
the wild-colour-picker delay is a transient, not a failure, if the round
continues afterwards.

## Writing new tests

- **Rules-only behaviour** goes in `TestRules.gd`. Build state with the
  `_stage()` helper (explicit hands + a forced top discard), call the rules
  API, and assert on state plus emitted events. Seed everything —
  `_fresh()` defaults to seed `1234` — so failures reproduce exactly.
- **Anything touching nodes** belongs in `TestIntegration.gd`. Add a
  `_test_*()` coroutine, register it in `_run_suite()`, and use
  `yield(_advance(seconds), "completed")` to let timers and tweens settle.
  Prefer driving the real handlers (`_game._try_play(view)`,
  `_game._on_draw_pressed()`) over poking internals.
- **Deterministic staging**: when you stage hands directly, remember that
  other scheduled timers (AI turns, armed reactions) may fire while you wait.
  Retire them by bumping `_game._ai_turn_token`, or avoid `yield()` between
  staging steps entirely.
- **Layout invariants** go in `TestLayout.gd`; keep them as pure functions of
  `TableLayout` so they stay fast and resolution-independent.

## Linting

```bash
pip install "gdtoolkit==3.5.*"
gdparse $(find Scripts Tests -name '*.gd')   # parse check
gdlint Scripts/ Tests/                       # style check
```

`gdlintrc` documents every deviation from the defaults and why. `gdformat` is
deliberately not used — see the note in that file.
