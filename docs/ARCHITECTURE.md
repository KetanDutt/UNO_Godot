# Architecture

## Overview

The game is intentionally small and scene-driven. `Scenes/Gameplay.tscn` owns the main table, buttons, and game-over overlay. `Scripts/GameManager.gd` coordinates nearly all gameplay systems, while each individual card is an instance of `Scenes/Card.tscn` using `Scripts/Card.gd`.

## Main Components

### `GameManager.gd`

Responsibilities:

- Load card textures.
- Build and shuffle the 108-card deck.
- Deal starting hands.
- Maintain player, AI, draw pile, and discard pile state.
- Validate moves against the active color and top discard value.
- Apply action-card effects.
- Run AI decisions.
- Update HUD labels, active color chip, draw/pass button state, and game-over overlay.
- Animate card movement and UI feedback.
- Generate lightweight runtime SFX with `AudioStreamSample`.
- Spawn simple `CPUParticles2D` effects for card plays and wins.

### `Card.gd`

Responsibilities:

- Store card color/value/texture metadata.
- Reveal or hide the card face.
- Emit click events to the parent `GameManager`.
- Handle hover lift animation and invalid-card shake feedback.
- Display playable-card highlighting.

### `Card.tscn`

A `Sprite` with an `Area2D` and `CollisionShape2D`. This fixes card input reliability by using physics picking instead of a zero-size UI button.

## State Model

- `DrawPile`: Array of card data dictionaries that have not been instantiated on the table.
- `DiscardData`: Card data history for cards played to the center.
- `PlayerCards`: Card scene instances in the player hand.
- `AICards`: Card scene instances in the AI hand.
- `CenterCards`: Card scene instances in the discard stack.
- `active_color`: The effective color to match. Wild cards update this value without changing their printed color.

## Reshuffling

When the draw pile is empty, every discard except the visible top card is shuffled back into `DrawPile`. Old center card nodes are removed to keep the scene tree light.

## Polish Systems

- Cards tween into hand positions and the center discard pile.
- Player cards lift on hover only when playable.
- Invalid plays shake the selected card and play an error tone.
- Action and wild card plays spawn color-matched particles.
- The active color chip pulses on turn changes.
- Runtime-generated SFX avoids adding binary audio dependencies.
