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

### Jumping in (house rule)

With **Jump-in** enabled, any player holding a card *identical* to the top of
the discard pile — same colour **and** same value — may play it immediately,
out of turn. The table then resumes from the jumper's seat. Wilds can never be
jumped in with, nobody can jump in on the untouched opening card, and a live
draw stack closes the window.

You jump in by simply clicking (or dragging) the twin card while another player
is deciding — it stays highlighted in your hand. The opponents have the same
right, but they react on a human-scale delay, so a fast click always beats
them. Hard opponents jump most reliably; Easy ones often miss the opening.

Cards you can legally play are lifted slightly and outlined. Illegal cards do
not respond to a click beyond a short shake.

You can play a card by clicking it, or by dragging it onto the discard pile.

## The opponents

Each match deals you a table of named, avatar'd opponents drawn from a roster —
Hugo the owl, Kira the robot, Bruno the cat and friends. Who you get is seeded
with the match, so the same table stays put for the whole match. They talk in
the status line ("Hugo is thinking…"), show their portrait on the seat plate
next to their card count, and their skill is set by the difficulty below.

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
catch you and you draw two as a penalty. You keep a short grace window — about
one second on Hard, a little longer on Easy — in which you can still press
**UNO!** to self-call and escape the catch. The opponents will catch you — how
reliably depends on the difficulty. You can catch them too, with **CATCH!**,
which only appears while someone is actually catchable. Opponents forget to
call UNO too (Easy ones especially) and the other CPUs will happily punish
them.

A seat plate showing `!` next to a hand count means that player is vulnerable
right now — including you, so watch your own plate.

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
| Target score | 100 / 200 / 300 / 500 / 750 | Points needed to win the match. |

### House rules

| Rule | Default | Effect |
| --- | --- | --- |
| Stacking | Off | Answer a Draw Two with another Draw Two (or escalate with a Wild Draw Four); the penalty accumulates and passes on. The pending total is shown on the discard pile. |
| Draw until playable | Off | Drawing keeps dealing you cards until one of them is legal, instead of exactly one. |
| Seven-Zero | Off | Playing a 7 swaps your hand with a player of your choice; playing a 0 rotates every hand in the direction of play. |
| Force play | Off | If you hold a legal card you must play it — drawing is disabled. |
| Jump-in | Off | A card identical to the top of the pile may be played out of turn by anyone; play resumes from the jumper. See above. |

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
| Jumps in with an exact twin | Sometimes | Usually | Always |
| Decision noise | High | Moderate | Low |

All three think for a short, slightly random time so play feels natural rather
than instant. That delay obeys the animation speed setting.

## Controls

| Action | Mouse / touch | Keyboard | Gamepad | TV remote |
| --- | --- | --- | --- | --- |
| Play a card | Click, or drag to the pile | `←` `→` to select, `Enter`/`Space` to play | D-pad or stick, `A` | `←` `→`, then `Select` |
| Use an action button | Click it | `↑`/`↓` to focus, `Enter` to press, `↑` again to return to the hand | D-pad, `A` | `↑` opens the buttons, `↑`/`↓` cycles, `Select` presses |
| Draw | Click the draw pile | `D` | `X` | via **DRAW** button |
| Pass | Click **PASS** | `P` | `Y` | via button |
| Call UNO | Click **UNO!** | `U` | `RB` | via button |
| Catch a missed UNO | Click **CATCH!** | `C` | — | via button |
| Sort your hand | Click **SORT** | `S` | `LB` | via button |
| Choose a wild colour | Click the colour | `←` `→`, `Enter` | D-pad, `A` | D-pad, `Select` |
| Pause / back | Click **MENU** | `Esc` | `B` or `Start` | `Back` |

**Playing on Android TV or Fire TV.** The game is fully playable with nothing
but the remote's D-pad, Select and Back — no touch, no mouse. Menus and the
colour picker move focus with the D-pad; during a hand, `↑` jumps from your
cards to the action buttons (marked with a glowing strip) and `↑` from the top
button returns to your hand. When you have nothing playable, the selection
starts on **DRAW** for you. `Back` pauses during play and goes back inside
menus.

The turn direction is shown by the coloured ring spinning around the discard
pile — it turns the way play passes and pulses when the turn changes. The
active seat's name plate is highlighted too.

## Statistics

The stats screen tracks matches played and won (with win rate), rounds played
and won (with round win rate), cards played, UNO calls and your best round
score. It can be reset independently of the rest of your settings.
