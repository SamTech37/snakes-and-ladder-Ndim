extends SceneTree

## Drives the real scene through whole games with random choices, animation off.
## Small boards on purpose: this checks that the turn loop is wired up, not that
## a random walk terminates on a big lattice.
## Run: godot --headless --script tests/test_play.gd

const Board = preload("res://src/board/board.gd")
const Pal = preload("res://src/palette.gd")
const TURN_CAP := 2000

func _initialize() -> void:
	for size in [PackedInt32Array([5, 5, 5]), PackedInt32Array([4, 4, 4, 4])]:
		var m = load("res://src/main/main.tscn").instantiate()
		m.size = size
		m.anim = false
		root.add_child(m)
		await process_frame

		var turns := 0
		while not m.won and turns < TURN_CAP:
			turns += 1
			m.do_roll()
			# Every marker is tinted by what it lands on -- untinted, the numbers say
			# nothing about which move is a snake.
			for i in m.moves.size():
				var idx := Board.coords_to_index(m.moves[i]["coords"], size)
				var want: Color = Pal.C_MOVE
				if idx == Board.total_cells(size) - 1:
					want = Pal.C_GOAL
				elif m.links.has(idx):
					var to := Board.index_to_coords(m.links[idx], size)
					var up := Board.dist_to_goal(to, size) < Board.dist_to_goal(m.moves[i]["coords"], size)
					want = Pal.C_LADDER if up else Pal.C_SNAKE
				assert(m.ghosts.get_child(i).material_override.albedo_color == want,
						"move %d marker is not tinted for what it lands on" % (i + 1))
			if not m.moves.is_empty():
				m.choose(randi() % m.moves.size())
			await process_frame

		assert(m.won, "random play never reached the goal on %s in %d turns" % [str(size), TURN_CAP])
		assert(m.coords == Board.goal_coords(size))
		print("%s won in %d random turns" % [str(size), turns])
		m.free()

	quit()
