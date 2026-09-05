extends SceneTree

## Run: godot --headless --script tests/test_board.gd

const Board = preload("res://src/board/board.gd")

func _initialize() -> void:
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

		# The open shell keeps only edges on the three far walls, so the near wall
		# never superimposes itself on the far one.
		var keep := Board.index_to_coords(0, size)  # camera on the + side of every axis
		var drawn := 0
		var total := 0
		for i in n:
			var c: PackedInt32Array = Board.index_to_coords(i, size)
			for k in size.size():
				if c[k] + 1 >= size[k]:
					continue
				total += 1
				if Board.on_open_faces(c, size, k, keep):
					drawn += 1
		assert(drawn < total / 2, "%s: open shell drew %d of %d edges" % [str(size), drawn, total])
		# Edges along the kept corner are all on far walls by definition.
		for k in size.size():
			assert(Board.on_open_faces(keep, size, k, keep))
		# The opposite corner is the near wall, and none of it may survive the cull.
		var near: PackedInt32Array = Board.goal_coords(size)
		for k in size.size():
			assert(not Board.on_open_faces(near, size, k, keep))

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

	print("board tests ok")
	quit()
