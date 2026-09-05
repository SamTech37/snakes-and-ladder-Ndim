extends RefCounted

# ponytail: preloaded as `Board` by its users rather than `class_name`, so
# `--script test_board.gd` runs without a built global class cache.

## Pure lattice math. No nodes, no state. Dimension count is data (`size`), not code.

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
## Two fan directions for a packed deck, alternating stack by stack. Straight from
## ideas/sketch.png: neighbouring decks are drawn sliced differently -- one piled
## upward, the next fanned sideways -- so a step along axis 3 is visibly a different
## kind of move from a step along axis 2, instead of both reading as "over there".
##
## Both carry a small negative z. The camera sits on +z, so plane 0 -- where the
## player starts -- ends up at the front of its deck rather than buried at the back,
## and no two planes are ever coplanar.
## Depth-dominant, because a 3D board is a **cube sliced into planes**: the slices
## recede into the screen with gaps cut between them, and the cube keeps its shape.
##
## These were briefly 1.55 *up* and 0.4 back, which made the deck a staircase
## climbing the screen instead of a cube. It also left only 2.0 units of depth across
## the whole stack, so switching the camera to perspective changed almost nothing --
## an 8% convergence at 25 units of camera distance.
##
## Pure depth, no lateral drift at all. A drift of 0.45 per slice was in here to tell
## neighbouring 4D decks apart, but it shears the stack: six slices each nudged
## sideways is a sheared prism, not a cube. A cube sliced into planes has to stay a
## cube, so the drift is gone and the two steps are for now identical.
##
## 4D decks therefore no longer look different from one another. That needs a device
## that does not deform the cube -- see CLAUDE.md.
const STACK_STEP_PILE := Vector3(0.0, 0.0, -1.6)
const STACK_STEP_FAN := Vector3(0.0, 0.0, -1.6)

## Direction whole stacks travel while packed. Diagonal rather than along x so a row
## of stacks reads horizontally at the isometric angle FOCUS uses.
const STACK_ROW_DIR := Vector3(0.70710678, 0.0, -0.70710678)


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


## Axes 3+ move whole stacks around. Axis 3 lines the stacks up in a row while they
## are packed, and once each stack has exploded into its own row it stacks those rows
## downward instead -- so a 4D board is a row of decks, and spread it is one row of
## planes per deck, rows under each other.
##
## Packed, the row runs along STACK_ROW_DIR rather than x: laid along x the stacks
## march off diagonally at the isometric angle, because the plane fan goes that way.
static func _stack_offset(c: PackedInt32Array, size: PackedInt32Array, spread: float) -> Vector3:
	if c.size() <= 3:
		return Vector3.ZERO
	var w := (size[0] + GAP) if size.size() > 0 else GAP
	var h := (size[1] + GAP) if size.size() > 1 else GAP
	var packed := STACK_ROW_DIR * (w * 1.8)
	var loose := Vector3(0.0, -h * 1.6, 0.0)
	var off := packed.lerp(loose, spread) * float(c[3])
	# ponytail: axes 4+ just keep marching downward at a widening stride, which is
	# over-generous while packed. A 6D board would want a real basis matrix; nothing
	# has needed one yet and there is no board that size to look at.
	var down := h * 1.6 * float(size[3])
	for k in range(4, c.size()):
		off.y -= float(c[k]) * down
		down *= float(size[k])
	return off


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

