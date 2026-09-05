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
static func gen_links(size: PackedInt32Array, count: int, rng: RandomNumberGenerator) -> Dictionary:
	var n := total_cells(size)
	var goal := n - 1
	var links := {}
	var used := {0: true, goal: true}
	var attempts := 0
	while links.size() < count and attempts < count * 100:
		attempts += 1
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		if used.has(a) or used.has(b) or a == b:
			continue
		if dist_to_goal(index_to_coords(a, size), size) == dist_to_goal(index_to_coords(b, size), size):
			continue
		links[a] = b
		used[a] = true
		used[b] = true
	return links
