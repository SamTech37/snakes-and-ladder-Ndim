# CLAUDE.md

## 1. Think Before Coding

State assumptions explicitly. If multiple interpretations exist, surface them — don't pick silently. If a simpler approach exists, say so. If something is unclear, stop and ask.

## 2. Simplicity First

Minimum code that solves the problem. No features, abstractions, configurability, or error handling beyond what was asked. If 200 lines could be 50, rewrite it. "Would a senior engineer call this overcomplicated?" — if yes, simplify.

## 3. Surgical Changes

Touch only what you must. Don't improve adjacent code, refactor what isn't broken, or reformat. Match existing style. Note unrelated dead code; don't delete it. Clean up only the orphans your own changes created. Every changed line should trace to the user's request.

## 4. Goal-Driven Execution

Define verifiable success criteria, then loop until met.

- "Add a rule" → write the assert that fails without it, then make it pass
- "Fix the bug" → write a check that reproduces it, then make it pass
- "Refactor X" → both suites pass before and after

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

## 5. Verification Before Claims

- NEVER claim work is complete, tests pass, or issues are fixed without running the actual verification command and showing output
- Use case-insensitive search by default (`grep -i`) unless specified otherwise
- When the user provides a spec with N items, verify each one individually and report [Unverified] for any you couldn't confirm

## 6. Nothing Moves Instantly

Every change to the camera or the pieces is tweened. An instant jump costs the
player their bearings and reads as a glitch rather than a move — a cut is not
feedback. This covers the view switch, `C` recentring, the die's hop, and a snake
or ladder dragging you somewhere.

Break it only with a stated reason, and say what the reason is in a comment. The
one standing exception is `anim = false`, which exists so `test_play.gd` can run
whole games without waiting on real time.

Camera angles are also **wrapped, never clamped**, and rebased to the nearest
equivalent angle before a tween. Orbiting nine times round and then recentring
should take the short way, not unwind nine turns on screen.

## 7. Use the Engine, Don't Rebuild It

Scenes, nodes, materials and the environment are authored in `.tscn` files, not constructed in `_ready()`. A script that instantiates its own camera, meshes and HUD leaves an empty scene tree and an editor with nothing to select — this was built that way once and had to be redone. Script only what cannot be authored by hand: procedural geometry, the turn loop, input.

Reach for the built-in before writing one: `Tween` over hand-rolled interpolation in `_process`, `Label3D` over billboard math, `SystemFont` over a bundled font file, `ImmediateMesh` over a `SurfaceTool` wrapper, built-in input actions (`ui_accept`) over new ones.

## 8. Long Jobs Run in Background

Every `godot --headless --script ...` run takes 30s to several minutes. Pass `run_in_background: true` — do not block the session, and do not chain `sleep` to poll. Batch independent runs into one background call.

The exception is anything needing `DISPLAY` (`shot.gd`, `test_readable.gd`): those take ~3s and **must** run in the foreground. Backgrounded, they die with exit 144.

## Running the Project

Godot **4.6.3** (Forward+, Jolt physics), binary at `~/.local/bin/godot`. No build step — GDScript is interpreted.

```bash
godot                                              # main scene: src/main/main.tscn
godot --headless --script tests/test_board.gd      # lattice math asserts
godot --headless --script tests/test_play.gd       # random play-throughs of the real scene
godot --headless --script tests/odds.gd            # E[rolls] per board, solved not guessed

# Scripts are interpreted, so a typo only surfaces when the scene loads. Parse-check
# before running anything long — a cross-node call breaks `:=` and nothing else says so.
godot --headless --check-only --script src/main/main.gd

# These two need a real display: --headless uses the dummy rasterizer and hangs.
# Run them in the FOREGROUND — a backgrounded GUI run dies with exit 144.
# --position parks the window off the desktop; both scripts also refuse focus, so
# they do not flash in front of whoever is using the machine.
DISPLAY=:0 godot --position -6000,-6000 --script tests/test_readable.gd -- 6,6,6
SNL_SEED=7 DISPLAY=:0 godot --position -6000,-6000 --script tests/shot.gd -- shots/a.png 6,6,6 0 roll
```

`shot.gd` args: output path, size, spread (`0` stacked / `1` exploded), `roll`, and an optional `yaw,pitch`. Screenshots go to `shots/`, which is gitignored.

Controls: `SPACE` roll, number keys pick a move — or pick the die when no move is pending — `X` spend a reroll, `TAB` switch SPREAD/FOCUS, `D` cycle board dimensions, `C` recentre the camera, `F3` debug view, `R` restart, drag to orbit, right-drag to pan, wheel to zoom.

Pan exists because the fit frames the whole board: zoomed in on a big lattice there is otherwise no way to reach the corner being played in. It is an offset on top of the fitted pivot, so a refit keeps it; `C` flies it back to zero along with the orbit.

`D` walks `Main.SIZES` — `[6,6,6]` → `[4,4,4,4]` → `[3,3,3,3,3]`. The higher-dimensional boards have to be reachable from inside the game, not only by editing an export.

`C` exists because orbit is free and it is easy to end up looking at nothing; it **flies** the camera back to the current view's own angle and forgets the parked one.

`F3` toggles a debug view: an arrow per lattice axis drawn from the start cell along the direction a `+1` step on that axis actually moves — **X red, Y green, Z blue, W yellow, V magenta, U cyan** — with a tick per cell, plus a HUD line giving yaw, pitch, zoom and spread. The directions are read back out of the projection rather than assumed, so they stay honest for W and V and right through the spread tween.

Orbit is **unclamped in both axes**. Pitch used to stop just short of overhead; past vertical the view is upside down and horizontal drag reverses, which is simply what a free orbit on an Euler rig does.

`SNL_SEED` pins the board so two screenshots can be compared; unset, it randomizes.

Every test script `extend SceneTree` and asserts. There is no test framework and none is wanted at this size — a failed `assert` exits non-zero, which is the whole contract.

## Architecture

```
src/main/main.tscn               the scene: every node, material and the environment
src/main/main.gd                 on Main: the turn loop and the input map, nothing else
src/board/board.gd               pure lattice math, static, no nodes, no scene
src/game/rules.gd                dice and what a cell does, static, measurable with no scene
src/board/board_view.gd          on Board: every line drawn — grids, frames, links, F3 gizmo
src/camera/cam_rig.gd            on CamRig: yaw, pitch, zoom, pan, the fit, the fly-to
src/ghost/ghosts.gd              on Ghosts: the numbered markers
src/ghost/ghost.tscn             one marker, instanced per legal move
src/hud/hud.gd                   on HUD: formats the text, changes no state
src/palette.gd                   every color in the game
tests/                           test_board.gd, test_play.gd, test_readable.gd, shot.gd
```

Each script owns one node and its children. Nothing reaches up the tree for a
neighbour: `main.gd:_ready()` wires the cross-references (`rig.board`, `view3d.rig`,
`ghosts.board`) in one place, and everything else talks through methods. `board.gd`
and `rules.gd` stay nodeless so the lattice and the odds can be measured headless.

**Cross-node calls kill `:=`.** A `var rig: Node3D` returns Variant from every method, so `var side := rig.perp(dir)` fails to parse with *"Cannot infer the type"* — the same gotcha as untyped containers. Annotate: `var side: Vector3 = rig.perp(dir)`.

### The one idea

The game is a lattice, and **dimension count is data, not code**. `Main.size` is a `PackedInt32Array`: `[10,10,10]` is the 3D board, `[9,9,9,9]` is a 4D one with eight directions per turn. Every function in `board.gd` takes `size` and derives everything from it — nothing is hardcoded to three axes.

### The board is a stack of 2D planes

`board.gd:coords_to_world(c, size, spread)` — axes 0 and 1 are position *within* a plane, axis 2 is which plane, axes 3+ move whole stacks around. `spread` lerps the layout between two arrangements, so switching views is one tweenable float rather than a second code path.

| | `spread = 0` (FOCUS) | `spread = 1` (SPREAD) |
|---|---|---|
| axis 2 | a deck, stepped by `stack_step()` | one row straight along +x |
| axis 3 | whole decks in a row along `STACK_ROW_DIR` | rows stacked downward, one per deck |
| camera | isometric (`A_ISO`) | face-on (`A_FLAT`) |

**The camera angle is half of what makes them two views.** Left on one angle, SPREAD is just FOCUS with wider spacing — the planes stay tilted parallelograms. Face-on, they come out as flat squares in a row. `_set_view()` tweens layout and angle together, and **parks the FOCUS angle** in `parked` so TAB-ing back does not dump you somewhere unfamiliar. **SPREAD is never remembered** — it always returns to face-on. It is the flat reference view and is supposed to be the same picture every time; restoring a remembered angle there is more disorienting, not less. `C` resets and clears the parked angle.

`A_ISO` is a gentle turn (0.30, −0.16), not a true isometric corner. It was 45°/35° for no reason I ever justified: seen from a corner a cube has no square face pointing at you, so every plane rendered as a leaning parallelogram.

The camera is **perspective** (`fov = 50`). Orthographic gives a deck zero convergence, so the depth between slices reads as skew rather than distance. The measurement that once condemned perspective was of a *solid* lattice; the board is separated planes now and that reason has expired.

`STACK_ROW_DIR` is diagonal rather than along x on purpose: it is exactly screen-right at the isometric angle, so a row of decks reads horizontally instead of marching off diagonally.

**The slice step is pure depth.** `(0, 0, -1.6)` — negative z because the camera sits on +z, so plane 0, where the player starts, is at the *front* of the deck. A 3D board is a **cube cut into planes** and it has to stay cube-shaped.

Two attempts have broken that and both were reverted:

- `(0, 1.55, -0.4)` made the deck a staircase climbing the screen, and left only 2.0 units of depth across the whole stack — so switching the camera to perspective was an 8% change and looked like nothing.
- `(0, 0.45, -1.6)` kept the depth but drifted each slice sideways to tell 4D decks apart. Six slices each nudged over is a sheared prism, not a cube.

`test_board.gd` asserts the step is pure `-z`. **Consequence: 4D decks currently look identical to each other.** `stack_step()` still exists and still alternates, but both branches return the same vector. Telling decks apart needs a device that does not deform the cube — `ideas/sketch.png` alternates piled and fanned stacks, which works on paper because each card keeps its shape; a per-slice drift does not.

**This replaced a projection that mapped axes straight onto x/y/z.** That one looked like a game and could not be played: `tests/test_readable.gd` measured **19–25% of cells sitting within 8 screen pixels of an unrelated cell** at every angle tried, on both `[6,6,6]` and `[10,10,10]`. A point in the volume did not say which cell it was, so no palette, culling or framing change could fix it — three rounds of those were tried and none moved the number. Shrinking the board made it *worse* (25% at `[6,6,6]` vs 18.8% at `[10,10,10]`), so board size was never the lever.

**Measure only the cells that are playable.** In FOCUS the lit plane is the board; the rest of the deck is dimmed background and is *meant* to overlap. Holding every cell in a packed deck apart pushed the plane step out to 3.5, at which point the deck was already most of the way to the exploded row and the two views stopped looking different at all. The metric looks at lit planes only.

Keep `ambig%` at 0 **at each view's own angle** — isometric for FOCUS, face-on for SPREAD. Off-angle rows are reported, not asserted: SPREAD orbited far from face-on will happily hit 100%, because a flat row seen edge-on is supposed to collapse. Any change to the step vectors, `STACK_ROW_DIR` or a view's home angle gets re-measured, not eyeballed.

### Rules

Pick a die, roll it for step size, then pick an axis and direction. A move that would leave the lattice **is not offered** — no clamping, because clamping would let you slide into the goal corner in three turns. If no move is legal the turn is forfeit. Ladders and snakes are plain cell-to-cell teleports, `{from_index: to_index}`, generated so no cell is both a source and a destination and neither start nor goal is touched.

`Rules.die_faces()` caps a die to `max(extent) - 1`: on a 5-wide axis a roll of 5 or 6 could never be legal anywhere, so a fixed d6 would waste a third of all turns.

**A bigger die is worse, and that is why there is a kit.** `tests/odds.gd` solves the whole lattice by value iteration: travel costs `2K(N-1)/(D+1)` rolls, and exact landing multiplies it by 2.5–3× — all of it endgame stall against the far wall. On `[6,6,6]` a lone d5 costs 13.4 rolls and a d6 costs 16.1; on `[4,4,4,4]` a d6 costs 19.1 against a d3's 9.6. Large faces are dead weight beside a wall.

`Rules.DICE` is therefore a **kit** — `[6, 3]`, capped and deduplicated per board by `Rules.kit()`, so `[6,6,6]` offers d5 and d3 while `[4,4,4,4]` offers one d3. Measured: `[6,6,6]` drops from 13.4 rolls to **8.59**. Rule-level fixes were measured too and lost — declining a turn 10.4, bouncing off the wall 10.4 — and neither is a decision the player gets to make.

**No d1.** With a d1 a forward move is legal from every cell but the goal, which deletes the endgame, the forfeits and every reroll. It is something to unlock, not to hand over at the start.

**Rerolls are the only escape hatch.** A roll that traps you — nothing legal, one forced move, or nothing that gets closer to the goal — grants a token (`Rules.grants_reroll()`); `X` spends one to roll again without spending a turn. Because the token arrives *on the roll that traps you*, you always hold one exactly when a losing move would otherwise be mandatory. That is the whole reason there is no separate "decline" option: it would be the same mechanism twice.

### Scene tree — `main.tscn`

| Node | Carries |
|---|---|
| `WorldEnvironment` | `Env_neon` — pure black, **linear tonemap, no glow**. Flat vector look: what a const says is what lands on screen. |
| `CamRig` → `Camera3D` | **Orthographic**, free orbit. `CamRig.rotation` is yaw/pitch, `Camera3D.size` zooms. Orthographic keeps the parallel edges the reference art has; the orbit is free because every fixed view is a subset of it. |
| `Grid` (MeshInstance3D) | `ImmediateMesh` filled by `_draw_board()` — plane grids, plane frames, goal star. `Mat_lines` (unshaded, vertex color, no culling). |
| `Shafts`/`Heads`/`Dots` (MultiMeshInstance3D) | The links, as real geometry: cylinder, cone, sphere, instanced per link by `_draw_links()`. |
| `Ghosts` (Node3D) | Parent for per-turn move markers. |
| `Player` (MeshInstance3D) | `SphereMesh` + `Mat_player`. |
| `HUD` (CanvasLayer) | `Margin → Rows → Status, Moves`. Mono `SystemFont`, dark `StyleBoxFlat` so text never fights the board. |

Line colors are consts at the top of `main.gd` (`C_SHELL_START`, `C_SHELL_GOAL`, `C_FRAME`, `C_HERE`, `C_LADDER`, `C_SNAKE`, `C_GOAL`). Don't hardcode a color inline; add a const. **Nothing goes above 1.0** — there is no glow pass to catch it, and the reference art in `ideas/` has no bloom in it either.

### Two views

`TAB` tweens `spread` between them over 0.5 s, so the deck visibly explodes and collapses instead of cutting.

- **FOCUS** (`spread = 0`) — the planes sit packed as a fanned deck. The plane the player is on draws at full brightness, so does the destination plane of every legal move, and **every other plane dims to `DIM`**. Dimmed, never hidden: dropping them is what made an earlier version stop being a view of the board at all.
- **SPREAD** (`spread = 1`) — the deck pulls apart into one row per stack, everything lit equally. One axis is one row; do not fold it into a grid to save width, that is what the wheel is for.

The player's own plane frame is drawn warm (`C_HERE`) in both; that is what says which plane you are standing on.

They have to stay visibly different. Two separate changes have collapsed the distinction by pushing `STACK_STEP` up until the packed deck was already nearly the exploded row.

## Godot 4.6 Gotchas Hit In This Project

- **Type inference needs typed containers.** `size` is a `PackedInt32Array`, not `Array`. With a plain `Array`, `size[k]` is a Variant and every `var x := ...` in `board.gd` fails to parse with *"Cannot infer the type of X variable"*.
- **`preload`, not `class_name`.** `board.gd` is pulled in with `const Board = preload("res://src/board/board.gd")`. A global `class_name` only resolves once the editor has built its class cache, which `--script` runs don't have.
- **`queue_free()` collects at end of frame.** A loop that takes many turns without awaiting a frame piles up every node it ever created — this ate several GB once. `_clear_ghosts()` uses `remove_child()` + `free()`.
- **`Tween.set_trans()` applies to tweeners created *after* it.** Chain it on the tweener (`t.tween_property(...).set_trans(...)`), not on the tween.
- **`add_child()` inside `_initialize()` does not run `_ready()` synchronously.** A `SceneTree` script must `await process_frame` before touching the scene, or every `@onready` var is still null. This cost a whole round of screenshots that silently had no move markers in them.
- **`--headless` cannot render.** It uses the dummy rasterizer; `--headless --rendering-driver vulkan` hangs outright. Screenshots need a real `DISPLAY`, and must run in the **foreground** — backgrounded GUI runs die with exit 144. Park the window with `--position -6000,-6000` plus `WINDOW_FLAG_NO_FOCUS`; it still renders and captures fine from off-screen, and stops stealing the desktop. (`xvfb-run` would be cleaner but Xvfb is not installed.)
- **Don't hand-roll geometry the renderer already does.** Links were first drawn as camera-facing quads in an `ImmediateMesh` and read as flat paper, because that is what they were. `MultiMeshInstance3D` with a `CylinderMesh` shaft, a zero-top-radius `CylinderMesh` cone and a `SphereMesh` dot gives real 3D that foreshortens and occludes properly — and needs no per-frame rebuild when the camera orbits.
- **`anim = false`** makes every hop instant so `test_play.gd` can run whole games without waiting on real-time tweens.

## Not Built Yet

Solo play only. No sound, menus, or save. Ghost markers are chosen by number key, not clicked — numbers still work when 5D offers ten directions. A cross-panel link in SPREAD shows a stub at each end but does not say which panel it lands in; FOCUS is where you read that.
