# Production Notes

## Production-Readiness Improvements Completed

- Replaced random one-off spawning with a real UNO-style deck and discard reshuffle.
- Fixed card clicking by replacing the ineffective zero-size `TextureButton` with `Area2D` input.
- Added action cards that were present in assets but missing in gameplay: Reverse, Draw Two, Wild, and Wild Draw Four.
- Added a color picker for player wild cards and AI wild-color selection logic.
- Added draw/pass turn handling to prevent unlimited drawing during a turn.
- Added status messaging, card/deck counts, active color display, replay reset, and responsive hand layout.
- Added keyboard, TV remote-style directional input, and controller support.
- Added modern main, pause, and how-to menus with focus support.
- Added tweens, hover effects, invalid move feedback, particles, generated SFX, and win feedback.
- Added architecture and gameplay documentation.
- Updated project naming and README.

## Suggested Future Improvements

These are good next steps if the project grows beyond a polished prototype:

1. **Match scoring**: Award points from remaining opponent cards and play to a target score.
2. **UNO call rule**: Add a timed UNO button and penalty for failing to call UNO at one card.
3. **Difficulty levels**: Tune AI between random, balanced, and strategic behavior.
4. **Settings menu**: Add SFX volume, animation speed, table selection, and accessibility options.
5. **Gamepad/touch affordances**: Add explicit focus states and larger mobile hit targets.
6. **Export pipeline**: Regenerate `build/` from a clean Godot export preset and document release steps.
7. **Automated smoke checks**: Add a lightweight GDScript parser/export validation step in CI once Godot is available in the build environment.

## Manual QA Checklist

Before release, verify the following in Godot 3.x:

- The main scene opens without import errors.
- A new game deals seven cards to both players.
- Highlighted player cards are playable and invalid cards shake.
- Draw is disabled after one draw until pass/play.
- Pass is enabled only after the player draws.
- Skip and Reverse grant another turn to the player who played them.
- Draw Two and Wild Draw Four make the opponent draw and lose a turn.
- Wild color picker appears for the player and updates the active color.
- AI can draw, play, pass, and choose wild colors.
- Discard reshuffle works when the draw pile is exhausted.
- Game-over overlay appears and Replay starts a clean game.
- Main menu starts the game and How to Play returns correctly.
- Esc/B/Start pauses and resumes while keyboard/controller focus remains usable.
- Keyboard, remote, and controller shortcuts select cards, play, draw, and pass.
