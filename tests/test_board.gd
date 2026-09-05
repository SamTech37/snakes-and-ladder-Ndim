extends SceneTree

## Run: godot --headless --script tests/test_board.gd

const Board = preload("res://src/board/board.gd")

## A failed `assert` does not stop a `--script` run: it abandons the function it is in and hands control back, so the checks live in their own function and sign off at the end. Without the signature the run exits 1 instead of looking clean.
var done := false


func _initialize() -> void:
	_checks()
	if not done:
		push_error("a check above failed")
		quit(1)
		return
	print("board tests ok")
	quit()


func _checks() -> void:
	for size in [PackedInt32Array([5, 5, 5]), PackedInt32Array([4, 4, 4, 4])]:
		var n: int = Board.total_cells(size)

		# Index <-> coords round-trips across the whole lattice.
		for i in n:
			assert(Board.coords_to_index(Board.index_to_coords(i, size), size) == i)

		# No legal move ever leaves the lattice.
		for i in n:
			var c: PackedInt32Array = Board.index_to_coords(i, size)
			for roll in range(1, 7):
				for m in Board.legal_moves(c, size, roll):
					var dest: PackedInt32Array = m["coords"]
					for k in size.size():
						assert(dest[k] >= 0 and dest[k] < size[k])
					assert(abs(dest[m["axis"]] - c[m["axis"]]) == roll)

		# Corner offers only outward moves; a roll wider than every axis offers none.
		var origin: PackedInt32Array = Board.index_to_coords(0, size)
		assert(Board.legal_moves(origin, size, 1).size() == size.size())
		assert(Board.legal_moves(origin, size, size[0]).is_empty())
		assert(Board.dist_to_goal(Board.goal_coords(size), size) == 0)

		# Every cell keeps its own point, stacked and exploded alike. The projection
		# this replaced put 19-25% of cells within 8 screen pixels of an unrelated
		# cell at every camera angle measured (tests/test_readable.gd), which is what
		# made the board unreadable. Collapsing two cells brings that straight back.
		for spread in [0.0, 1.0]:
			var seen := {}
			for i in n:
				var w: Vector3 = Board.coords_to_world(Board.index_to_coords(i, size), size, spread)
				var key := "%.3f,%.3f,%.3f" % [w.x, w.y, w.z]
				assert(not seen.has(key), "%s spread %.0f: cells %d and %d land on one point"
						% [str(size), spread, seen.get(key, -1), i])
				seen[key] = i

			# Neighbours inside a plane stay exactly one unit apart in both layouts.
			for i in n:
				var c: PackedInt32Array = Board.index_to_coords(i, size)
				for k in mini(2, size.size()):
					if c[k] + 1 >= size[k]:
						continue
					var d := c.duplicate()
					d[k] += 1
					var step: float = Board.coords_to_world(c, size, spread) \
							.distance_to(Board.coords_to_world(d, size, spread))
					assert(is_equal_approx(step, 1.0), "%s: axis %d step is %f" % [str(size), k, step])

		# Exploded, every plane is flat on z = 0 and pulled clear of its neighbour.
		if size.size() > 2:
			for i in n:
				var w: Vector3 = Board.coords_to_world(Board.index_to_coords(i, size), size, 1.0)
				assert(is_zero_approx(w.z), "%s: cell %d is off the plane when spread" % [str(size), i])
			var p0: Vector3 = Board.coords_to_world(Board.index_to_coords(0, size), size, 1.0)
			var next := Board.index_to_coords(0, size)
			next[2] = 1
			assert(Board.coords_to_world(next, size, 1.0).x - p0.x >= float(size[0]),
					"%s: exploded planes overlap" % str(size))
		assert(Board.GAP >= 1.0)
		# Slices stack straight back with no sideways drift, so the board stays a cube
		# cut into planes rather than a sheared prism.
		for step in [Board.STACK_STEP_PILE, Board.STACK_STEP_FAN]:
			assert(step.z < -1.0, "slices must recede, not climb")
			assert(is_zero_approx(step.x) and is_zero_approx(step.y), "drift shears the cube")

		# Links never chain, never touch start or goal, and stay within their span.
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var links: Dictionary = Board.gen_links(size, 12, rng, 5)
		assert(links.size() == 12)
		for a in links:
			assert(a != 0 and a != n - 1)
			assert(links[a] != 0 and links[a] != n - 1)
			assert(not links.has(links[a]))
			var span: int = Board.manhattan(Board.index_to_coords(a, size), Board.index_to_coords(links[a], size))
			assert(span <= 5, "%s: link spans %d, cap was 5" % [str(size), span])

	done = true
