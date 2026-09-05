extends SceneTree

## Drives the real scene through whole games with random choices, animation off.
## Small boards on purpose: this checks that the turn loop is wired up, not that
## a random walk terminates on a big lattice.
## Run: godot --headless --script tests/test_play.gd

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")
const Pal = preload("res://src/palette.gd")
const TURN_CAP := 2000

func _initialize() -> void:
	for size in [PackedInt32Array([5, 5, 5]), PackedInt32Array([4, 4, 4, 4])]:
		var m = load("res://src/main/main.tscn").instantiate()
		m.size = size
		m.anim = false
		root.add_child(m)
		await process_frame

		# The kit is what the player picks between, so the pick has to reach the roll.
		var kit := Rules.kit(size)
		m._pick_die(kit.size() - 1)
		assert(m.die_faces() == kit[kit.size() - 1], "picking a die did not change the roll")
		m._pick_die(0)

		var turns := 0
		while not m.won and turns < TURN_CAP:
			turns += 1
			var before_tokens: int = m.rerolls
			var at: PackedInt32Array = m.coords
			m.do_roll()

			# A trapped roll -- nothing legal, one forced move, or nothing that gets
			# closer -- has to hand back a token, because that token is the only thing
			# standing between the player and a mandatory losing move.
			var trapped := Rules.grants_reroll(m.moves, at, size)
			assert(m.rerolls == before_tokens + (1 if trapped else 0),
					"reroll granted on the wrong roll")
			assert(not trapped or m.rerolls > 0, "trapped with no way out")

			# Spending a token buys another roll, not another turn.
			if trapped and m.rerolls > 0:
				var t: int = m.turns
				var held: int = m.rerolls
				m.reroll()
				assert(m.turns == t, "a reroll cost a turn")
				assert(m.rerolls <= held, "a reroll did not spend its token")
			# Every marker is tinted and shaped by what it lands on -- plain, the
			# numbers say nothing about which move is a snake.
			for i in m.moves.size():
				var idx := Board.coords_to_index(m.moves[i]["coords"], size)
				var kind := ""
				if idx == Board.total_cells(size) - 1:
					kind = "GOAL"
				elif m.links.has(idx):
					var to := Board.index_to_coords(m.links[idx], size)
					var up := Board.dist_to_goal(to, size) < Board.dist_to_goal(m.moves[i]["coords"], size)
					kind = "LADDER" if up else "SNAKE"
				var g: Node3D = m.ghosts.get_child(i)
				var want: Color = Pal.landing_color(kind)
				assert(g.get_node("Number").modulate == want,
						"move %d marker is not tinted for what it lands on" % (i + 1))
				var shape: MeshInstance3D = g.get_node(m.ghosts.SHAPE[kind])
				assert(shape.visible and shape.material_override.albedo_color == want,
						"move %d marker is not shaped for what it lands on" % (i + 1))
			if not m.moves.is_empty():
				m.choose(randi() % m.moves.size())
			await process_frame

		assert(m.won, "random play never reached the goal on %s in %d turns" % [str(size), TURN_CAP])
		assert(m.coords == Board.goal_coords(size))
		print("%s won in %d random turns" % [str(size), turns])
		m.free()

	quit()
