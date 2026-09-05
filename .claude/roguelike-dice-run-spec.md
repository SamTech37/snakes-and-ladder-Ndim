# Roguelike dice run — design spec

Covers TODO items 2 (events / foes), 3 (procedural generation, partially), 4 (D → D+1 continue). Written against the game as it exists in `CLAUDE.md`: the lattice, the kit, the reroll token, the tray.

## Pitch

You climb dimensions. Each floor is a lattice you cross from start cell to goal corner, and the only resource you have is a handful of dice — the same dice that move you are the dice you fight with. A big die is measurably bad at travel (a d6 is dead weight against the far wall; `odds.gd` proves it) and the best thing you can hold in 比大. So every die you win off a foe makes you stronger at one job and worse at the other, and the kit only holds D of them — two on the 2D floor, five on the 5D floor. Something is walking toward you the whole time, one cell for every roll you make, rerolls included, and when it reaches you it picks the fight instead of you picking it. Reach the goal and the floor's boss is standing on it. Win and you ascend to D+1 with everything you carry. Lose your last die and the run is over.

## Core loop

**The turn:**

1. Pick a die from the kit (click it on the tray, or number key).
2. `SPACE` rolls it. The die tumbles, comes up on a face value.
3. Legal moves appear as numbered ghost markers — one per axis/direction that stays inside the lattice. Pick one.
4. The player tweens to the cell. Landing resolves through `Rules.landing()`: plain floor, ladder, snake, **fixed foe → fight**, **goal → boss fight**.
5. **The roamer steps one cell toward you.** It steps after *every* roll — a spent reroll advances it too. If it ends on your cell, it starts a fight.

**The floor:** cross the lattice, take or dodge the fixed foes on the way, stay ahead of the roamer, beat the boss on the goal cell, ascend.

**The run:** endless. 2D → 3D → 4D → 5D → 6D → … Kit and reroll tokens carry across floors. The run ends when the kit is empty. Target 3–5 minutes per floor; board extent for D > 5 is chosen by running `odds.gd` and picking the N that holds E[rolls] in the band the earlier floors sit in.

## The fight

A foe is three things: **a die** (a list of face values), **a set of minigames**, and **a commit-order trait**.

**One contest, one roll each.** Not a mode switch — a beat inside the turn.

- You commit one die from your kit. **The die you commit is the die you stake.** Lose and the foe takes that die.
- Win and the foe's die is offered. Kit is capped at D; over cap you choose one to discard.
- Both dice roll. The minigame decides the winner.

**Commit-order traits** — the 分蛋糕 principle, one side frames and the other chooses:

| Trait | v0 | What the player does |
|---|---|---|
| (iii) OPEN | ✅ | Foe announces the minigame. You pick which die to commit. |
| (iv) TELL | ✅ | Foe's die is shown. You pick the minigame from its set. |
| (i) BLIND-DIE | later | You commit a die, *then* the foe names the game. |
| (ii) BLIND-GAME | later | You name the game, *then* the foe reveals its die. |

The two known-information traits ship first because they teach the vocabulary — which die suits which contest — and the blind two are only interesting once the player has that vocabulary to bet on.

**Minigames in v0**, each a class behind one interface so 對子 / 吹牛 / 猜結果 / 中位數 / 標準差 / 分堆 / 猜大小 are additions and not rewrites:

- **比大** — higher roll wins. A d[6,6,6,6] is the best thing you can hold here and nearly useless for travel.
- **比小** — lower roll wins. Small dice, the travel-efficient ones, are the champions.
- **奇偶** — the framer calls odd or even; the caller wins if the *sum* matches. A die whose faces are all one parity is a lock; an even-face-count die is a coin flip.

Three is enough to make die choice non-obvious, because no die wins all three.

**Interface** (shape only, not final code):

```
Minigame:
  name() -> String                       # displayed, and the word in the fight banner
  play(mine: Array, theirs: Array) -> bool   # rolled values in, did I win
  favours(faces: Array) -> float         # 0..1, for foe AI and for the HUD hint
```

`favours()` exists so the foe can pick sensibly in the traits where it frames, and so nothing has to hardcode "d6 is good at 比大" in two places.

**The boss** is best-of-three: three different minigames from its set, one committed die per round. Losing the match costs the die committed in the deciding round; winning takes the boss die. A lost boss match can be rematched immediately as long as the kit is not empty — so a weak kit does not get stuck, it bleeds out. **That is the run's real death condition,** and it is why sprinting past every optional fight is not free.

## The decision

Three decisions stack, and none of them has a dominant answer:

**Which die to roll this turn.** Travel wants small faces near the far wall (exact landing, no overshoot) and big faces in open space. `odds.gd` already measures this: on `[6,6,6]` a lone d5 costs 13.4 rolls, a d6 costs 16.1, and picking between d6 and d3 costs 9.4. The kit that travels fastest is a spread of small and large.

**Which die to stake in a fight.** The stake is the commitment, so the question is not only "which die wins this contest" but "which die can I afford to lose". Committing your d3 to 比大 is a near-certain loss of a die you were happy to lose; committing your d6 is a likely win that risks your best fighter. Neither is right in general.

**Whether to fight at all.** Fixed foes sit on cells and can be steered around — the cheap move is sometimes the one into the foe. Skipping them keeps your kit intact and leaves you at the boss with the kit you started the floor with. Taking them costs rolls (the roamer closes) and risks dice, and pays in dice.

**Why no option dominates:** the kit is one pool doing two jobs with opposite requirements, and the cap is D so you cannot hold a specialist set for each. Every acquisition is a substitution.

## Systems & feedback loops

**R1 — Spoils (reinforcing, positive).** Win a fight → better die → win more fights. Braked by the cap: over D dice you must discard, so the kit's *shape* is bounded even when your luck is not.

**R2 — Attrition (reinforcing, negative).** Lose a die → fewer options, worse coverage → lose more. Deliberately not fully braked. Escapes: fixed foes are optional, the roamer is outrun-able, and a hopeless run ends fast — which is the point of a short floor.

**B1 — Kit cap = D (balancing).** Room grows exactly as the board does. Ascending is a genuine reward (a slot) and a genuine threat (a bigger lattice) at once.

**B2 — One pool (balancing, and the spine).** A fight-optimal kit (big faces) travels badly. A travel-optimal kit (small faces) fights badly at 比大 and well at 比小. There is no configuration that is good at everything.

**B3 — Rerolls now cost time.** The trap-roll token still arrives exactly when a losing move would otherwise be mandatory, but spending it advances the roamer a cell. The escape hatch was free; now it is paid for in distance.

**The interesting interaction** is B2 crossing the roamer. A brawler kit travels slowly, so the roamer catches it more often, so it fights more, so it gets more dice — B2 flips reinforcing under chase pressure. The run therefore bifurcates into two readable lines:

- **Sprinter** — small faces, dodge everything, arrive at the boss early with D dice you started with, and win a best-of-three with weak tools.
- **Brawler** — big faces, get caught constantly, arrive late and strong, but stall badly against the far wall where the exact-landing endgame eats the rolls and the roamer is right behind you.

Both reach the boss. They fail differently. That is the design working.

## Legibility

**On screen, always:**

- **The roamer never dims.** It draws at full brightness even when it stands on a dimmed plane — the one exception to the FOCUS dimming rule, and it needs a comment saying so. Everything else on a background plane is scenery; this thing is a clock.
- **Distance to the roamer in cells**, in the status line. In a projected 4D view you cannot count that by eye, and a chase you cannot measure is not a clock, it is an ambush.
- **The roamer's next step** — a short line from it toward the axis it will move along. It steps deterministically (greedily reduces lattice distance to you, ties broken by lowest axis), so the player can plan against it.
- **The kit on the tray**, as now, with each die's face list readable on the picked die. Custom faces mean the silhouette alone no longer tells you the die — the bipyramid still has one side per face, but the values have to be legible on the picked die.
- **Floor D and the cap** — the cap *is* D, so one number carries both.

**During a fight:** the foe's die appears on the opposite side of the frame from the tray, facing your kit — the fight happens on the tray, in dice, not in a text box. The minigame name is one line. Nothing else.

**Deliberately hidden:** the foe's roll until both sides have committed, and in the later blind traits, the half of the framing the trait withholds. Nothing about your own state is ever hidden.

## Design decisions

- **The stake is the die you commit.** Rejected: the foe takes a random die, or you pick which to lose after losing. Staking the committed die makes one choice carry both the odds and the risk, and it means a fight can be entered cheaply on purpose.
- **Cap = D, everything carries.** Rejected fixed cap of 3 (ascending would only ever get worse) and D+1 (slack that removes the first hard choice).
- **Roamer is the ante, not a turn budget.** A budget is a number; a chaser is on the board. Cost accepted: N-D pathing and the never-dim rule.
- **Roamer scales by dice, not by speed** (recommended default, with the speed left as a knob). A two-step chaser in a projected 4D view cannot be anticipated, and an unanticipatable clock is just noise. Later floors give it better dice, so being caught gets worse without being less readable.
- **Rerolls advance the roamer.** Otherwise the token is a free rewind and the clock does not tick during the endgame stall, which is exactly where it needs to.
- **Custom face lists from the start.** Consequence, stated plainly: `Rules.die_faces()` stops applying to won dice — a face too large to ever be legal on this board is a wasted roll, and a wasted roll already grants a reroll token. So an oversized die is playable, punishing, and still a monster in 比大. `odds.gd`'s value iteration must iterate a face list instead of `1..die`; that harness has to keep working, because it is how floor extents and the roamer's tuning get chosen.
- **Losing the boss is not a wall.** Rematch immediately; each attempt costs a die. A weak kit dies at the boss instead of being locked out of the game with nothing to do.
- **Chain reactions come from dice and foes, not from board topology.** TODO item 3 asks for Balatro-style chain reactions; this design puts that surface in the kit (face lists interacting with minigames and with travel odds) rather than in non-uniform tiles. Link generation stays as it is in v0.
- **Boss best-of-three, everything else single.** Gives each floor a pacing curve without making routine fights a minute long.

## Open questions — playtest only

- **Banked reroll tokens may be dominant.** Everything carries, so a stockpile trivialises the exact-landing endgame on every later floor. Watch for it; the brakes if it happens are a cap on held tokens, or tokens costing two roamer steps instead of one.
- **Roamer catch frequency.** One step per roll against a player who moves 1–max faces per roll: is it a background hum or a leash? Tune the start distance per floor, not the speed.
- **Is the roamer readable at 4D+?** The distance line and the next-step marker are the bet. If they are not enough, the roamer is a 3D-and-below feature.
- **Are three minigames enough** to make the kit shape a real puzzle, or does one die trivially dominate two of the three?
- **Fixed foes vs roamer vs boss** — the user's own note: a few rounds of playtest will tell us who to cut. All three ship so that choice is informed.
- **How much of the floor is spent fighting** at 3–5 minutes a floor. If fights are more than a third of it, the travel game is a corridor between fights.
- **Floor extents beyond 5D** — `odds.gd` picks N to hold the E[rolls] band, but 6D legibility is already the known wall (5D is small and sparse at both home angles).

## Out of scope for v0

| Deferred | Earns its place when |
|---|---|
| Blind commit orders (i) and (ii) | The player reliably knows which die suits which contest — the bet needs a vocabulary to bet against. |
| 對子 / 吹牛 / 猜結果 / 中位數 / 標準差 / 分堆 | The three shipped minigames prove the interface and one of them turns out to be dead weight. |
| Die modifier keywords (weighted, loud) | Face lists alone stop producing distinguishable builds. |
| A shop / between-floor economy | Fights alone fail to produce enough kit variety across a run. |
| Procedural link generation with a difficulty curve, guaranteed-reachable snakes, foe placement from the same sampler | Uniform rejection sampling visibly produces dull or unfair floors in playtest. |
| Non-uniform tile size and non-uniform grid (TODO item 3) | The lattice itself is proven boring — currently the variety budget is spent on dice, not topology. |
| d1 as an unlock | There is an unlock system; a d1 deletes the endgame if handed over early. |
| Meta-progression between runs | Runs are fun enough to repeat without it. |
| 4D deck differentiation | Independent of this spec; still blocked on a device that does not shear the cube. |
