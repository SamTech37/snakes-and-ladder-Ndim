# Worklog

## 2026-09-06 — playtest round (`feat/roguelike`, 8 commits)

Everything here came out of the first hand-played runs. Nothing was found by a test; the tests came after, to hold each one down.

### Dead ends found by playing

**A kit could be unable to reach the goal at all.** Two `[3,3,3]` dice roll 3 and only 3, so one cell short of the goal there is no move, for ever, and every reroll comes up 3 again. `Rules.reach()` is the gcd of a die's faces and must be 1 for every die the game hands out — moves go both ways along an axis, so that is the whole condition. `damaged()` upholds it too, and `test_minigames.gd` walks every pool and every chain of damage down to the bottom. Two authored dice were locked.

**The kit cap made it likely.** One die per axis meant a win over the cap forced a discard, which is how a kit becomes two of the same die and nothing else. The cap is gone; `TRAY_DICE` is only how many fit on screen.

**A boss with two contests deadlocked its own third round.** Best-of-three insisted on a fresh contest each round, ran out, and drew an empty list with SPACE doing nothing.

**A fight could take your last die and end the run on the first foe.** The last die is never taken now: it breaks, losing its largest face, and only shatters at two faces.

### The frontend rule

Every drift bug this round was one bug: state changed and something forgot to tell the view. The tray showed a die already taken; the contest panel re-derived "what is left" and disagreed with the code that commits it. `CLAUDE.md` rule 7 now says the frontend is a function of the backend, `_refresh_hud()` redraws the tray as well, and `_fight_view()` hands the screen the contest list rather than letting it work one out.

### Also

Results wait to be read (`YOU WON` / `YOU LOST` / `FLOOR CLEARED`, then SPACE). Climbing a floor animates — the old board falls away, the new one assembles out of its planes. 奇偶 takes a caller, so it is two contests. Draws are thrown again. Freebie dice lie on the board. `?` opens a glossary. `SHIFT+R` restarts at the first floor. The chaser steps after your move, never between the roll and it. The opening view is the fitted one — the first fit ran before the HUD had been laid out, which is why `C` appeared to "recentre" a fresh game.

### Verified

Six suites, all green: `test_board`, `test_play`, `test_minigames` (new — every contest case by case), `test_fight`, `test_run`, `odds`. `test_readable` 0.0% at both home angles on all four boards.

Not verified: a full run played to a natural death.

### Next

1. **Playtest again.** Now that the dead ends are gone, whether the chase and the fights are actually *fun* is still unmeasured.
2. **Procedural generation** (job iii) — still uniform rejection sampling for links, foes and gifts alike.
3. **The blind commit orders** (i) and (ii).
4. Roamers rolling their die to move, and being carried by links, per `TODO.md`.

## 2026-09-05 — the run (`feat/roguelike`, 3 commits)

Design interview first: `.claude/roguelike-dice-run-spec.md`. TODO items 2 and 4 are built; item 3 is deliberately still uniform sampling.

### Done

**A die is a list of faces.** `6` became `[1,2,3,4,5,6]`, so a die won off a foe can be `[1,1,5,5]` (streaky) or `[3,3,3]` (certain) and roll through the same code. The kit stopped being derived from `size` and became run state. `odds.gd` walks the list and prints the same numbers it printed before — 8.59 / 9.57 / 8.09 / 8.87 — which is the proof the refactor changed nothing.

**Fights.** A foe stands on a cell, a boss on the goal. One contest, one roll each; the boss takes two of three. **The die you commit is the die you stake** — lose and the foe takes that one, so the question is never only which die wins. `src/game/minigames.gd` holds BIGGER / SMALLER / EVEN SUM behind one interface; ties go to the foe. A foe either names the contest and leaves you the die (`OPEN`) or shows its die and leaves you the contest (`TELL`) — the 分蛋糕 split.

**The kit cap is the dimension count.** Winning a die over the cap means dropping one, so the kit's shape is bounded even when your luck is not. One pool: the dice that move you are the dice you fight with, and `odds.gd` already proves a big die travels badly while a big die is the best thing to hold in BIGGER.

**The chaser.** Travel was free, so a floor was won by anyone patient enough. It steps one cell after **every roll, rerolls included**. It never dims, it draws the step it is about to take, and the HUD carries `chaser N` in cells. It scales by its dice, not its speed.

**The climb.** Floor number and dimension count are the same number. The run opens on 2D with **one die** — measured, not chosen: alone, a d3 costs 11.61 rolls against a d6's 13.82, and `odds.gd` now asserts it. Beating the boss climbs to D+1 with the kit intact. Losing the boss costs a die and it comes straight back, so a weak kit bleeds out rather than getting locked out. The run ends when the last die is gone.

**Input, separated.** `SPACE` means one thing — commit: roll, reroll, stake, or drop. The number keys are the board's and only the board's; dice and contests moved to the arrows. `X` is gone: a reroll *is* another throw.

**A fight announces itself three ways** — a sting, the music swapping to a fight loop, and a ring on the cell. Each round plays an opposite sound and an opposite-coloured ring; the status line turns foe-orange for the duration; `notice` says what the fight cost or paid until the next roll.

### Verified

`test_board`, `test_play` (foes and chaser off — it is the liveness check), `test_fight` (contests on hand-built rolls, stake, cap, boss, run over, the key map), `test_run` (the chase closes and keeps its promise, a reroll advances it, a catch starts a fight, the climb keeps the kit, `carry_tokens` both ways), `odds` unchanged, `test_readable` 0.0% at both home angles with the chaser and foes drawn.

**A failed `assert` does not fail a `--script` run** — it prints, abandons the function it is in, and the process still exits 0. `test_fight` and `test_run` sign each check off and exit 1 on a missing signature; `test_board` and `test_play` still rely on the old assumption.

Not verified: nobody has played a full run by hand.

### Next

1. **Playtest.** Catch frequency, whether banked tokens dominate (`carry_tokens` is the flag), whether three contests are enough, and which of foe / chaser / boss to cut.
2. **The blind commit orders** (i) and (ii) — commit first, learn after. Only a bet once the vocabulary exists.
3. **Procedural generation** (job iii). Still uniform rejection sampling: no difficulty curve, no guarantee a snake is reachable, foes placed by the same blunt sampler.
4. **The reference art in `ideas/` is still only half used** — the plates carry perspective-warped and wave-displaced grids; the board planes are still flat square grids. The deck arrangement in `sketch.png` is built.

## 2026-09-05 — playability (`feat/playable`, 6 commits)

### Done

**Split `main.gd`.** It was 759 lines holding the turn loop, the board mesh, the camera, the HUD and the input map. Now one script per node: `board_view.gd` draws, `cam_rig.gd` owns every camera number, `ghosts.gd` the markers, `hud.gd` formats text and changes no state, `rules.gd` the nodeless rules, `main.gd` the turn loop and input. `_ready()` wires the cross-references in one place. Verified invisible: identical `test_readable` numbers, identical PNG md5.

**Measured the odds.** `tests/odds.gd` solves the lattice by value iteration through the shipped `Board.legal_moves()`. Travel costs `2K(N−1)/(D+1)` rolls; exact landing multiplies it by 2.5–3×, all of it stall against the far wall. A bigger die is worse — on `[4,4,4,4]` a d6 costs 19.1 rolls against a d3's 9.6.

**Dice kit.** `Rules.DICE = [6, 3]`, capped and deduplicated per board. `[6,6,6]` fell from 13.4 expected rolls to **8.59**. No d1: it makes a forward move legal everywhere but the goal, deleting the endgame. Unlock material.

**Rerolls.** A roll that traps you — nothing legal, one forced move, or nothing that gets closer — grants a spare die. `X` or a click spends one to roll again without spending a turn. The token arrives on the roll that traps you, so a losing move is never mandatory; that is why there is no separate decline rule.

**Dice tray.** `src/dice/tray.gd`, parented to the camera, bottom-left, constant screen size. Wireframe bipyramids with one side per face — a d5 is a five-sided diamond. Picked one bright and turning, the other dim. Spares sit beside them and kick when earned. Click to pick or spend.

**Affordance.** One status line; move list, legend and controls behind `ESC`. Markers carry colour, shape (cube / cone up / cone down / diamond) and a line to where a link would drag you. The goal is a wireframe beacon in hot amber, not a pale asterisk.

**Sound.** `Audio` autoload, six sounds synthesised at startup plus an A-minor pad loop. No audio files. `M` mutes. Drop a CC0 loop at `res://assets/bgm.ogg` to override.

**Effects.** Roll number lands on the die that was thrown (it used to pop over the player's head with a descending burst, which read as damage). Landing ring, win burst. All tweened into the board mesh.

**Restart moved to `SHIFT+R`.** A bare `R` sits beside every key you actually use.

### Verified

`test_board`, `test_play` (marker colour and shape, reroll grant timing, no turn cost, six non-silent buffers), `odds` 8.59 / 9.57, `test_readable` 0.0% ambiguity at both home angles.

Not verified: the sound audibly — headless has no device, only the sample peaks were checked. Nobody has played a full game by hand since the tray landed.

### Added after
`D` now cycles 3D → 4D → 5D → 2D. Both new boards are data only, no code changed: `[10,10]` is one plane (kit d6/d3, 8.87 expected rolls), `[3,3,3,3,3]` is nine decks (kit d2, 8.09). Both measure 0% ambiguity at their home angles, and `test_play` runs all four. 5D is legible but small and sparse — the layout spreads axes 4+ downward at a widening stride.

### Next

1. **Events and foes** (job ii). Nothing designed yet. `Rules.landing()` is the single hook — add a case there and a colour to the palette, and markers pick up shape and colour for free. Unlock rules for extra dice and reroll tokens belong here, as does the d1.
2. **Procedural generation** (job iii). `Board.gen_links()` is still uniform rejection sampling with a span cap. No difficulty curve, no guarantee a snake is ever reachable.
3. **CC0 synthwave BGM.** Hook is in; no track sourced.
4. **4D decks look identical.** `stack_step()` alternates but both branches return the same vector, because any per-slice drift shears the cube. Needs a device that keeps the cube's shape — `ideas/sketch.png` alternates piled and fanned stacks.
5. **Unused reference art.** The plates in `ideas/` carry perspective-warped and wave-displaced grids; the board planes are still flat square grids.
