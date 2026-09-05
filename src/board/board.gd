extends RefCounted

# ponytail: preloaded as `Board` by its users rather than `class_name`, so
# `--script test_board.gd` runs without a built global class cache.

## Pure lattice math. No nodes, no state. Dimension count is data (`size`), not code.

## Gap between projected copies for axes 3+ (grid-of-grids projection).
const GAP := 2.0


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


## Axes 0,1,2 map to x,y,z. Axes 3,4,5 offset x,y,z by a whole lattice width,
## so a 4D board draws as a row of cubes (tesseract as small multiples).
static func coords_to_world(c: PackedInt32Array, size: PackedInt32Array) -> Vector3:
	# ponytail: caps out at 6 dimensions, where axis 6 would collide with axis 0.
	# Past that a projection needs a real basis matrix, not a modulo.
	var xyz := [0.0, 0.0, 0.0]
	for k in c.size():
		var lo := k % 3
		var val := float(c[k])
		if k >= 3:
			val *= size[lo] + GAP
		xyz[lo] += val
	return Vector3(xyz[0], xyz[1], xyz[2])


## True when the edge running from `c` along axis `k` lies on the *open* shell:
## at least `n - 2` of the other axes sitting on the extreme named by `keep`.
##
## `keep[j]` is the far extreme of axis j from wherever the camera is. Drawing only
## those turns the lattice into an open box seen from inside — three walls, no near
## wall. Drawing all six instead superimposes the near grid on the far one, which is
## the moire that made the board unreadable no matter how the colors were tuned.
static func on_open_faces(c: PackedInt32Array, size: PackedInt32Array, k: int, keep: PackedInt32Array) -> bool:
	var n := size.size()
	if n <= 2:
		return true
	var pinned := 0
	for j in n:
		if j != k and c[j] == keep[j]:
			pinned += 1
	return pinned >= n - 2


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

