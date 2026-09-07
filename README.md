# UNO Godot

A polished, single-player UNO-style card game built with Godot. Play against a computer opponent, match colors and values, use action cards strategically, and race to empty your hand first.

Live build: https://ketandutt.github.io/UNO_Godot/

## Highlights

- Complete 108-card UNO-style deck distribution.
- Human vs. computer gameplay loop.
- Number cards, Skip, Reverse, Draw Two, Wild, and Wild Draw Four support.
- Smart draw pile / discard pile reshuffle handling.
- AI opponent that prioritizes strong action cards and chooses wild colors based on its hand.
- Playable-card highlighting and hover lift animations.
- Smooth card movement, discard animations, turn feedback, color picker, particles, and runtime-generated SFX.
- Responsive card layout for different window sizes.
- Modern main, pause, how-to, and settings menus with keyboard/controller focus support.
- Keyboard, TV remote-style D-pad, controller, mouse, and touch-friendly controls.
- UNO call, missed-UNO penalty, sort-hand, and SFX toggle quality-of-life features.
- In-game status text, active color indicator, hand counts, deck count, pass flow, replay flow, and game-over summary.

## How to Play

1. Start the project and wait for both players to receive seven cards.
2. On your turn, play a card that matches the active color or the top discard value.
3. Wild cards can be played at any time and let you choose the next active color.
4. If you cannot or do not want to play, press **DRAW**. After drawing once, play the drawn card if valid or press **PASS**.
5. Empty your hand before the computer does.

## Controls

- **Mouse / touch**: select a highlighted card to play it.
- **Keyboard / TV remote**: Left/Right selects cards, Enter/Space plays, D draws, P passes, U calls UNO, S sorts, Esc opens pause/back.
- **Controller**: D-pad/left stick selects cards, A plays, X draws, Y passes, RB calls UNO, LB sorts, B/Start opens pause/back.
- **DRAW**: draw one card during your turn.
- **PASS**: end your turn after drawing.
- **Replay / R**: restart after the game ends.

## Requirements

This project uses the Godot 3 scene format (`format=2`) and `project.godot` config version 4. Use a Godot 3.x editor/export template for best compatibility.

## Running Locally

1. Install Godot 3.x.
2. Open this repository as a Godot project.
3. Run the main scene: `Scenes/Gameplay.tscn`.

## Project Structure

```text
Assets/                  Card art, table art, fonts, and source asset notes
Scenes/                  Godot scenes
  Card.tscn              Interactive card node with collision input
  Gameplay.tscn          Main game scene
Scripts/                 GDScript gameplay code
  Card.gd                Card state, hover feedback, and click handling
  GameManager.gd         Deck rules, turns, AI, UI, animation, SFX, and VFX
docs/                    Design, gameplay, and production documentation
build/                   Existing exported web build artifacts
```

## Documentation

- [Gameplay and Rules](docs/GAMEPLAY.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Production Notes](docs/PRODUCTION_NOTES.md)

## Credits

- Card/table assets are stored in `Assets/Uno Game Assets/`.
- Roboto font files are included under `Assets/Roboto/` with their license.

## License

See [LICENSE](LICENSE).
