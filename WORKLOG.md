# Worklog

## 2026-09-06 — playtest round (`feat/roguelike`, 9 commits)

**Verdict: the whole is worse than the navigation game it was built on.** Playable, but confusing to play and to work on. Session 1.5 is subtraction.

### Fixed
- kit could be unreachable — `[3,3,3]` twice moves in threes for ever. `Rules.reach()` (gcd of faces) must be 1 for every die; `damaged()` upholds it.
- kit cap forced discards that caused it. Cap gone.
- boss struck contests off its own list, then ran out mid-match.
- a fight could take your last die on the first foe. Last die breaks instead, shatters at two faces.
- tray crashed once the kit passed 8 dice. It is a window now.
- chaser used one foe per floor, so wins handed you copies of one die.
- boss win paid nothing, not even its die.
- tray showed dice already taken — `_refresh_hud()` redraws it; `_fight_view()` hands the screen its contest list.
- opening view was framed before the HUD had a size, so `C` "recentred" a fresh game.

### Added
Results wait for SPACE. Climb animates. 奇偶 takes a caller (two contests). Draws re-thrown. Gift dice on the floor. `?` glossary. `SHIFT+R` restarts at floor 1. Chaser steps after your move, not between roll and move.

### Tests
`test_minigames` (every contest, case by case) and `test_deadend` (whole runs, something to press at every step, per-floor budget) are new. Seven suites green. `test_readable` 0.0% at both home angles.

### Not verified
A full run to a natural death.

### Next
`TODO.md` items 5–7 (session 1.5), then 8–9 (session 2).

## 2026-09-05 — the run (`feat/roguelike`, 3 commits)

Spec: `.claude/roguelike-dice-run-spec.md`. TODO 2 and 4 built; 3 untouched.

### Added
- **a die is a list of faces**, not a count — `[1,1,5,5]` is streaky, `[3,3,3]` certain. `odds.gd` printed the same 8.59 / 9.57 / 8.09 / 8.87 after the refactor, which is the proof it changed nothing.
- **fights** — foe on a cell, boss on the goal. One contest, one roll each; boss takes two of three. The die you commit is the die you stake. OPEN names the contest and leaves you the die; TELL shows its die and leaves you the contest.
- **kit cap = dimension count** (since removed — it caused unreachable kits).
- **the chaser** — one cell per roll, rerolls included (since condemned in playtest, see TODO 5).
- **the climb** — floor number and dimension count are the same number. Opens on 2D with one die, measured: a lone d3 costs 11.61 rolls against a d6's 13.82.
- **input separated** — SPACE commits, number keys are the board's alone, dice and contests on the arrows. `X` gone.
- **a fight announces itself** — sting, music swap, ring on the cell.

### Learned
A failed `assert` does not fail a `--script` run: it abandons its function and the process still exits 0. Every test file signs its checks off now.

## 2026-09-05 — playability (`feat/playable`, 6 commits)

### Added
- **split `main.gd`** (759 lines) into one script per node. Verified invisible: identical `test_readable` numbers, identical PNG md5.
- **`tests/odds.gd`** — solves the lattice by value iteration through the shipped rules. Travel costs `2K(N−1)/(D+1)` rolls; exact landing multiplies it 2.5–3×, all of it stall against the far wall.
- **dice kit** — a bigger die is *worse*: on `[4,4,4,4]` a d6 costs 19.1 rolls against a d3's 9.6. `[6,6,6]` fell from 13.4 to 8.59.
- **rerolls** — granted by the roll that traps you, so a losing move is never mandatory. That is why there is no separate decline rule.
- **dice tray** — wireframe bipyramids, one side per face, parented to the camera. The kit as objects, because none of it survived being text.
- **markers** carry colour, shape and a line to where a link drags you. Goal is a beacon.
- **sound** — six synthesised effects plus a pad loop, no audio files.
- **`D` cycles boards** — `[10,10]` (8.87 rolls) and `[3,3,3,3,3]` (8.09) are data only, no code changed.

### Learned
`queue_free()` collects at end of frame — a loop that never yields piles up every node it made. `--headless` cannot render. `Tween.set_trans()` applies to tweeners made after it.
