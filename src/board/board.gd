extends RefCounted

# ponytail: preloaded as `Board` by its users rather than `class_name`, so
# `--script test_board.gd` runs without a built global class cache.

## Pure lattice math. No nodes, no state. Dimension count is data (`size`), not code.

## Axis letters, in lattice order. Here rather than in a view script because they are
## the lattice's own vocabulary: the HUD and the debug gizmo both name axes with them.
const AXIS_NAMES := "XYZWVU"

## Blank space between neighbouring planes once they are pulled apart, in cells.
const GAP := 2.0

## Offset from one stacked plane to the next: straight back, which at the default
## isometric view slides each plane down and left of the one in front, so the stack
## reads as a fanned deck of cards.
##
## Kept short on purpose. Widening it to 3.5 did drive the all-cells collision count
## to zero, but a deck spread that far apart is already most of the way to the
## exploded row and the two views stopped being distinguishable. Cells on the dimmed
## planes are background, not targets: what has to be legible in FOCUS is the lit
## plane, and tests/test_readable.gd measures exactly that.
## How a deck of planes is sliced, alternating deck by deck. Straight out of ideas/sketch.png: neighbouring decks are drawn differently -- one piled square, the next fanned out like a hand of cards -- so a step along axis 3 is visibly a different kind of move from a step along axis 2 instead of both reading as "over there".
##
## Both carry a negative z. The camera sits on +z, so plane 0 -- where the player starts -- ends up at the front of its deck rather than buried at the back, and no two planes are ever coplanar.
##
## PILE is pure depth, because a 3D board is a **cube sliced into planes**: the slices recede into the screen with gaps cut between them, and the cube keeps its shape. It was briefly 1.55 *up* and 0.4 back, which made the deck a staircase climbing the screen and left only 2.0 units of depth across the whole stack -- so switching the camera to perspective was an 8% change and looked like nothing. A 3D board only ever uses this one.
##
## FAN slides each slice along its own plane as it recedes, which is what the sketch draws. A drift like this was in here once applied to *every* deck and was reverted, correctly: uniformly applied it just makes every deck a sheared prism and still tells none of them apart. The signal is the **contrast** -- it is only worth anything next to a piled deck, so only every other deck gets it.
const STACK_STEP_PILE := Vector3(0.0, 0.0, -1.6)
const STACK_STEP_FAN := Vector3(0.45, -0.22, -1.4)

## Direction whole decks travel across a packed row. Diagonal rather than along x so the row reads horizontally at the isometric angle FOCUS uses.
const STACK_ROW_DIR := Vector3(0.70710678, 0.0, -0.70710678)

## Deck pitch while packed, as a multiple of the board's own width and height. Decks used to be strung out along a single row at 1.8 board-widths each, which on a 4D board put four decks across 30-odd units of a board four cells wide: the lattice ended up a thin smear across the screen with the camera fit backed off far enough to hold all of it. They pack as a grid now, and close.
const PACK_X := 1.08
const PACK_Y := 1.15


static func total_cells(size: PackedInt32Array) -> int:
	var n := 1
	for s in size:
		n *= s
	return n


static func coords_to_index(c: PackedInt32Array, size: PackedInt32Array) -> int:
	var i := 0
	var stride := 1
	for k in size.size():
		i += c[k] * stride
		stride *= size[k]
	return i


static func index_to_coords(i: int, size: PackedInt32Array) -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(size.size())
	var rest := i
	for k in size.size():
		c[k] = rest % size[k]
		rest /= size[k]
	return c


## How many planes the board is made of: axes 2+ flattened.
static func plane_count(size: PackedInt32Array) -> int:
	var n := 1
	for k in range(2, size.size()):
		n *= size[k]
	return n


## Which plane a cell sits on: axes 2+ flattened. This is plane *identity* -- what
## gets lit or dimmed together -- and every axis above 1 takes part in it.
static func plane_of(c: PackedInt32Array, size: PackedInt32Array) -> int:
	var p := 0
	var stride := 1
	for k in range(2, c.size()):
		p += c[k] * stride
		stride *= size[k]
	return p


## How deep into its own stack a cell sits: axis 2 alone. Layout must use this and
## not plane_of -- flattened, axis 3 would both spread a plane along the row and
## offset its whole stack, sending a 4D board off diagonally instead of into rows.
static func depth_of(c: PackedInt32Array) -> int:
	return c[2] if c.size() > 2 else 0


## Which deck a cell belongs to: axes 3+ flattened. A 3D board has exactly one.
static func stack_of(c: PackedInt32Array, size: PackedInt32Array) -> int:
	var s := 0
	var stride := 1
	for k in range(3, c.size()):
		s += c[k] * stride
		stride *= size[k]
	return s


## Alternating decks are sliced the other way round, which is the only thing saying
## the 4th axis is not just more of the 3rd.
static func stack_step(c: PackedInt32Array, size: PackedInt32Array) -> Vector3:
	return STACK_STEP_FAN if stack_of(c, size) % 2 == 1 else STACK_STEP_PILE


## The board is a stack of 2D planes. Axes 0 and 1 are position *within* a plane;
## axis 2 is which plane; axes 3+ lay whole stacks out, alternating across then down.
##
## `spread` lerps the layout: at 0 the planes are stacked a `PLANE_GAP` apart like a
## deck of cards, at 1 they are pulled apart into one row per stack, flat on z = 0.
## One number, so the view switch is a tween rather than a second code path.
##
## Every cell keeps its own point in both layouts. The projection this replaced
## mapped axes straight onto x/y/z and put 19-25% of cells within 8 screen pixels of
## an unrelated cell at every angle measured -- a point in the volume did not say
## which cell it was, which no amount of colour or culling could fix. See
## tests/test_readable.gd.
static func coords_to_world(c: PackedInt32Array, size: PackedInt32Array, spread := 0.0) -> Vector3:
	var p := float(depth_of(c))
	var in_plane := Vector3(c[0], _in_plane_y(c), 0.0)
	var stacked := in_plane + stack_step(c, size) * p
	# Straight along x, because SPREAD looks at the board face-on: the planes have to
	# come out as a flat row of squares, not a tilted row that is only the packed
	# deck with wider gaps.
	var exploded := in_plane + Vector3.RIGHT * p * (size[0] + GAP)
	return stacked.lerp(exploded, spread) + _stack_offset(c, size, spread)


static func _in_plane_y(c: PackedInt32Array) -> float:
	return float(c[1]) if c.size() > 1 else 0.0


## How many decks the board is made of: axes 3+ flattened. A 3D board has exactly one, a [4,4,4,4] has four, a [3,3,3,3,3] has nine.
static func deck_count(size: PackedInt32Array) -> int:
	var n := 1
	for k in range(3, size.size()):
		n *= size[k]
	return n


## Axes 3+ move whole decks around, one direction per axis. **4D is a row of cubes, 5D is a grid of them** -- the way a 4D tensor is a row of 3D blocks and a 5D one is a 2D arrangement of the same, which is how you read the thing without pretending to see four axes at once.
##
## Axis 3 lays decks along the row, axis 4 stacks those rows downward, and each axis above that takes the next direction in turn at a stride wide enough to clear everything the axes below it already occupy -- so a 6D board is a row of grids. That last part is the honest limit of this layout: past 5D it is tiling in two directions, not showing you a sixth.
##
## Axes 4+ used to march downward at a stride that multiplied by every axis in turn, which threw a 5D board's nine decks across many times the board's own size and left the lattice a scatter of specks.
static func _stack_offset(c: PackedInt32Array, size: PackedInt32Array, spread: float) -> Vector3:
	if c.size() <= 3:
		return Vector3.ZERO
	var w := (size[0] + GAP) if size.size() > 0 else GAP
	var h := (size[1] + GAP) if size.size() > 1 else GAP
	var dirs := [STACK_ROW_DIR * (w * PACK_X), Vector3(0.0, -h * PACK_Y, 0.0)]
	var stride := [1.0, 1.0]
	var packed := Vector3.ZERO
	for k in range(3, c.size()):
		var d := (k - 3) % 2
		packed += dirs[d] * stride[d] * float(c[k])
		stride[d] *= float(size[k])
	# Exploded, each deck is already a full row of planes, so they can only stack downward.
	var loose := Vector3(0.0, -h * 1.6, 0.0) * float(stack_of(c, size))
	return packed.lerp(loose, spread)


static func manhattan(a: PackedInt32Array, b: PackedInt32Array) -> int:
	var d := 0
	for k in a.size():
		d += absi(a[k] - b[k])
	return d


static func goal_coords(size: PackedInt32Array) -> PackedInt32Array:
	var c := PackedInt32Array()
	for s in size:
		c.append(s - 1)
	return c


static func dist_to_goal(c: PackedInt32Array, size: PackedInt32Array) -> int:
	var d := 0
	for k in c.size():
		d += size[k] - 1 - c[k]
	return d


## Every in-bounds move of exactly `roll` steps. No clamping: a move that would
## leave the lattice is simply not offered, which keeps the exact-landing tension.
static func legal_moves(c: PackedInt32Array, size: PackedInt32Array, roll: int) -> Array:
	var moves := []
	for k in size.size():
		for dir in [1, -1]:
			var t: int = c[k] + dir * roll
			if t < 0 or t >= size[k]:
				continue
			var dest := c.duplicate()
			dest[k] = t
			moves.append({"axis": k, "dir": dir, "coords": dest})
	return moves


## `count` teleports as {from_index: to_index}. Positive delta = ladder, negative = snake.
## A cell is never both a source and a destination (no chains), and start/goal are untouched.
##
## `max_span` caps the Manhattan reach of a link (0 = uncapped). Endpoints drawn from
## anywhere in the lattice produce links that cross the whole board: visually a
## hairball of full-width lines, and a single ladder skipping most of the game.
static func gen_links(size: PackedInt32Array, count: int, rng: RandomNumberGenerator, max_span := 0) -> Dictionary:
	var n := total_cells(size)
	var goal := n - 1
	var links := {}
	var used := {0: true, goal: true}
	var attempts := 0
	# Rejection sampling: a span cap throws away most random pairs, so the budget has
	# to be generous or short boards come back with fewer links than asked for.
	while links.size() < count and attempts < count * 500:
		attempts += 1
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		if used.has(a) or used.has(b) or a == b:
			continue
		var ca := index_to_coords(a, size)
		var cb := index_to_coords(b, size)
		if max_span > 0 and manhattan(ca, cb) > max_span:
			continue
		if dist_to_goal(ca, size) == dist_to_goal(cb, size):
			continue
		links[a] = b
		used[a] = true
		used[b] = true
	return links


## Cells to stand a foe on. Never the start, never the goal -- the goal is the boss's -- and never either end of a link, because a cell already carrying a teleport has something to say when you land on it and two of those would fight for the marker.
static func gen_foes(size: PackedInt32Array, count: int, rng: RandomNumberGenerator,
		links: Dictionary) -> PackedInt32Array:
	var n := total_cells(size)
	var taken := {0: true, n - 1: true}
	for a in links:
		taken[a] = true
		taken[links[a]] = true
	var out := PackedInt32Array()
	var attempts := 0
	while out.size() < count and attempts < count * 500:
		attempts += 1
		var c := rng.randi_range(0, n - 1)
		if taken.has(c):
			continue
		taken[c] = true
		out.append(c)
	return out
