# Gameplay

Everything the game does at the table, and every option you can change.

## The goal

Empty your hand. When you do, the round ends and you score the value of every
card still held by the other players. Keep winning rounds until you reach the
target score (500 by default) and you win the match.

## A turn

On your turn you may play one card that matches the **active colour** or the
**value** of the top card of the discard pile. Wild cards may be played at any
time and let you name the next colour.

If you cannot — or would rather not — play, press **DRAW**. You may play the
card you just drew if it is legal, otherwise press **PASS** to end your turn.

Cards you can legally play are lifted slightly and outlined. Illegal cards do
not respond to a click beyond a short shake.

You can play a card by clicking it, or by dragging it onto the discard pile.

## Card values

| Card | Effect | Score |
| --- | --- | --- |
| 0–9 | None. | Face value |
| Skip | The next player loses their turn. | 20 |
| Reverse | Flips the direction of play. In a two-player game it acts as a Skip. | 20 |
| Draw Two | The next player draws two and loses their turn. | 20 |
| Wild | Choose the next active colour. | 50 |
| Wild Draw Four | Choose the colour; the next player draws four and loses their turn. | 50 |

The deck is the standard 108 cards: 19 of each colour (one 0, two each of 1–9),
two each of Skip, Reverse and Draw Two per colour, four Wilds and four Wild
Draw Fours.

## Calling UNO

When you are about to drop to one card, press **UNO!**. You may call it while
holding two cards (before you play), or immediately after playing down to one.

If you reach one card without calling, you are **vulnerable**: an opponent can
catch you and you draw two as a penalty. The opponents will catch you — how
reliably depends on the difficulty. You can catch them too, with **CATCH!**,
which only appears when someone is actually catchable.

A seat plate showing `!` next to a hand count means that player is vulnerable
right now.

## Scoring

The round winner scores the total value of every card left in the other
players' hands. First player to the target score wins the match. The round
summary screen shows the per-player breakdown.

## Running out of cards to draw

When the draw pile empties, the discard pile is shuffled back into it, leaving
the top card face up. If even that is not possible — everything is in someone's
hand — and no player can move, the round is a stalemate and is awarded to
whoever holds the fewest points. This is rare, but the game will not lock up
when it happens.

## Settings

Reachable from the main menu or by pausing (`Esc`). Changes apply immediately
and persist to `user://settings.cfg`.

### Match

| Setting | Values | Notes |
| --- | --- | --- |
| Opponents | 1–3 | Applies from the next round. |
| Difficulty | Easy / Normal / Hard | See below. |
| Target score | 200 / 300 / 500 / 750 | Points needed to win the match. |

### House rules

| Rule | Default | Effect |
| --- | --- | --- |
| Stacking | On | Answer a Draw Two with another Draw Two; the penalty accumulates and passes on. The pending total is shown on the discard pile. |
| Draw until playable | Off | Drawing keeps dealing you cards until one of them is legal, instead of exactly one. |
| Seven-Zero | Off | Playing a 7 swaps your hand with a player of your choice; playing a 0 rotates every hand in the direction of play. |
| Force play | Off | If you hold a legal card you must play it — drawing is disabled. |

### Display and accessibility

| Setting | Default | Effect |
| --- | --- | --- |
| Animation speed | 1.0× | 0.5×–2.0×. Scales *all* timing: card movement, AI thinking time, summary delays. |
| Table | 0–4 | Five felt designs. |
| Hints | On | Highlights playable cards and explains why a move was rejected. |
| Colour-blind marks | Off | Adds a letter (R/B/G/Y) beside the active colour and on the colour picker. |
| Screen shake | On | Turn off if motion is uncomfortable. |
| Particles | On | Turn off for a calmer table or on a weak machine. |
| High contrast | Off | Heavier borders and brighter text. |

### Audio

Separate master, music and effects sliders. Music ducks automatically under
important cues.

## Difficulty

| | Easy | Normal | Hard |
| --- | --- | --- | --- |
| Card choice | Mostly random | Scores every legal card | Scores every legal card |
| Holds Wilds for a good moment | No | Yes | Yes |
| Tracks colours you are void in | No | No | Yes |
| Calls UNO reliably | Sometimes | Usually | Almost always |
| Catches your missed UNO | Rarely | Often | Almost always |
| Decision noise | High | Moderate | Low |

All three think for a short, slightly random time so play feels natural rather
than instant. That delay obeys the animation speed setting.

## Controls

| Action | Mouse / touch | Keyboard | Gamepad |
| --- | --- | --- | --- |
| Play a card | Click, or drag to the pile | `←` `→` to select, `Enter`/`Space` to play | D-pad or stick, `A` |
| Draw | Click the draw pile | `D` | `X` |
| Pass | Click **PASS** | `P` | `Y` |
| Call UNO | Click **UNO!** | `U` | `RB` |
| Catch a missed UNO | Click **CATCH!** | `C` | — |
| Sort your hand | Click **SORT** | `S` | `LB` |
| Pause / back | Click **MENU** | `Esc` | `B` or `Start` |

Menus are fully keyboard and gamepad navigable.

## Statistics

The stats screen tracks rounds played, rounds won, win rate, cards played,
UNO calls and successful catches. It can be reset independently of the rest of
your settings.
