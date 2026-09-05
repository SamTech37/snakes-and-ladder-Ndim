# Worklog

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

### Next

1. **Events and foes** (job ii). Nothing designed yet. `Rules.landing()` is the single hook — add a case there and a colour to the palette, and markers pick up shape and colour for free. Unlock rules for extra dice and reroll tokens belong here, as does the d1.
2. **Procedural generation** (job iii). `Board.gen_links()` is still uniform rejection sampling with a span cap. No difficulty curve, no guarantee a snake is ever reachable.
3. **CC0 synthwave BGM.** Hook is in; no track sourced.
4. **4D decks look identical.** `stack_step()` alternates but both branches return the same vector, because any per-slice drift shears the cube. Needs a device that keeps the cube's shape — `ideas/sketch.png` alternates piled and fanned stacks.
5. **Unused reference art.** The plates in `ideas/` carry perspective-warped and wave-displaced grids; the board planes are still flat square grids.
