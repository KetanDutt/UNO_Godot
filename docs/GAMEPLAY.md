# Gameplay and Rules

UNO Godot is a two-player UNO-style game: the human player competes against one computer opponent.

## Objective

Be the first player to play every card in your hand.

## Turn Flow

1. The active player may play one valid card.
2. A valid card must match the active color, match the top discard value, or be a Wild card.
3. If the human player draws a card, they may play it if it is valid or press **PASS**.
4. The computer draws when it has no valid card. If the drawn card is valid, the computer immediately plays it; otherwise, it passes.

## Cards

The runtime deck uses the standard 108-card UNO-style distribution:

- Four colors: Red, Yellow, Green, and Blue.
- One zero card per color.
- Two copies of values 1-9 per color.
- Two Skip cards per color.
- Two Reverse cards per color.
- Two Draw Two cards per color.
- Four Wild cards.
- Four Wild Draw Four cards.

## Action Card Behavior

Because this is a two-player game, Skip and Reverse both cause the opponent to lose a turn, so the current player plays again.

- **Skip**: opponent loses their next turn.
- **Reverse**: acts as Skip in two-player mode.
- **Draw Two**: opponent draws two cards and loses their next turn.
- **Wild**: player chooses the next active color.
- **Wild Draw Four**: player chooses the next active color; opponent draws four cards and loses their next turn.

## Current Implementation Scope

The game focuses on a smooth single-player experience. It does not currently include stacking Draw cards, challenge rules for Wild Draw Four, online multiplayer, or a scoring match system.
