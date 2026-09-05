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

## 6. Use the Engine, Don't Rebuild It

Scenes, nodes, materials and the environment are authored in `.tscn` files, not constructed in `_ready()`. A script that instantiates its own camera, meshes and HUD leaves an empty scene tree and an editor with nothing to select — this was built that way once and had to be redone. Script only what cannot be authored by hand: procedural geometry, the turn loop, input.

Reach for the built-in before writing one: `Tween` over hand-rolled interpolation in `_process`, `Label3D` over billboard math, `WorldEnvironment` glow over a custom shader, `ImmediateMesh` over a `SurfaceTool` wrapper, built-in input actions (`ui_accept`) over new ones.

## 7. Long Jobs Run in Background

Every `godot --headless --script ...` run takes 30s to several minutes. Pass `run_in_background: true` — do not block the session, and do not chain `sleep` to poll. Batch independent runs into one background call.

## Running the Project

Godot **4.6.3** (Forward+, Jolt physics), binary at `~/.local/bin/godot`. No build step — GDScript is interpreted.

```bash
godot                                              # main scene: src/main/main.tscn
godot --headless --script tests/test_board.gd      # lattice math asserts
godot --headless --script tests/test_play.gd       # random play-throughs of the real scene
```

Controls: `SPACE` roll, number keys pick a move, drag to orbit, wheel to zoom, `R` restart.

Both test scripts `extend SceneTree` and assert. There is no test framework and none is wanted at this size — a failed `assert` exits non-zero, which is the whole contract.

## Architecture

```
src/main/main.tscn + main.gd     scene and its script, together
src/ghost/ghost.tscn             numbered move marker, instanced per legal move
src/board/board.gd               pure lattice math, static, no nodes, no scene
tests/                           test_board.gd, test_play.gd
```

### The one idea

The game is a lattice, and **dimension count is data, not code**. `Main.size` is a `PackedInt32Array`: `[10,10,10]` is the 3D board, `[9,9,9,9]` is a 4D one with eight directions per turn. Every function in `board.gd` takes `size` and derives everything from it — nothing is hardcoded to three axes.

`board.gd:coords_to_world()` projects axes 0–2 onto x/y/z and offsets axes 3–5 by a whole lattice width, so a 4D board draws as a row of cubes with the w-edges spanning between them. It caps at six dimensions, where axis 6 would collide with axis 0; past that the modulo needs to become a real basis matrix.

### Rules

Roll a d6 for step size, then pick an axis and direction. A move that would leave the lattice **is not offered** — no clamping, because clamping would let you slide into the goal corner in three turns. If no move is legal the turn is forfeit. Ladders and snakes are plain cell-to-cell teleports, `{from_index: to_index}`, generated so no cell is both a source and a destination and neither start nor goal is touched.

`die_faces()` caps the d6 to `max(extent) - 1`: on a 5-wide axis a roll of 5 or 6 could never be legal anywhere, so a fixed d6 would waste a third of all turns.

### Scene tree — `main.tscn`

| Node | Carries |
|---|---|
| `WorldEnvironment` | `Env_neon` — black bg, ACES, glow/bloom. **This is the arcade look**; no shader is written. |
| `CamRig` → `Camera3D` | Orbit rig. `CamRig.rotation` is yaw/pitch, camera sits at `+Z * cam_dist`. |
| `Grid` (MeshInstance3D) | `ImmediateMesh` filled by `_draw_board()`, plus `Mat_lines` (unshaded, vertex color). |
| `Ghosts` (Node3D) | Parent for per-turn move markers. |
| `Player` (MeshInstance3D) | `SphereMesh` + `Mat_player`. |
| `HUD` (CanvasLayer) | `Margin → Rows → Status, Moves`. Fonts and colors are theme overrides in the scene. |

Line colors are consts at the top of `main.gd` (`C_GRID`, `C_LADDER`, `C_SNAKE`, `C_GOAL`). Don't hardcode a color inline; add a const.

## Godot 4.6 Gotchas Hit In This Project

- **Type inference needs typed containers.** `size` is a `PackedInt32Array`, not `Array`. With a plain `Array`, `size[k]` is a Variant and every `var x := ...` in `board.gd` fails to parse with *"Cannot infer the type of X variable"*.
- **`preload`, not `class_name`.** `board.gd` is pulled in with `const Board = preload("res://src/board/board.gd")`. A global `class_name` only resolves once the editor has built its class cache, which `--script` runs don't have.
- **`queue_free()` collects at end of frame.** A loop that takes many turns without awaiting a frame piles up every node it ever created — this ate several GB once. `_clear_ghosts()` uses `remove_child()` + `free()`.
- **`Tween.set_trans()` applies to tweeners created *after* it.** Chain it on the tweener (`t.tween_property(...).set_trans(...)`), not on the tween.
- **Glow needs headroom.** `glow_hdr_threshold` must sit below the emissive color's brightness, and glow is Forward+ only. Neon colors are deliberately > 1.0.
- **`anim = false`** makes every hop instant so `test_play.gd` can run whole games without waiting on real-time tweens.

## Not Built Yet

Solo play only. No sound, menus, or save. The 4D board renders through the offset projection with no slice/channel UI. Ghost markers are chosen by number key, not clicked — numbers still work when 5D offers ten directions.
