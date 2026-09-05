extends SceneTree

## How long a game takes, solved rather than guessed.
##
## Value iteration over the whole lattice: E[rolls] from the start cell to the goal
## under a player who always picks the best move and the best die. Driven through
## Board.legal_moves() and Rules.kit(), so it measures the rules that ship rather than
## a copy of them that can drift.
##
## Links are left out on purpose -- they are random per game, and what is being
## measured here is the cost the *lattice* imposes: travel is 2K(N-1)/(D+1) rolls, and
## the exact-landing endgame multiplies it. That multiplier is the number worth
## watching, and it is the one a die or a rule change moves.
##
## Rerolls are left out for the same reason: they only ever lower this, so the number
## printed here is the ceiling a real game plays under.
##
## Run: godot --headless --script tests/odds.gd

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")

## What a game on the default board should cost. Below this the board is a formality;
## above it, a slog. The measured 13.4 rolls for a lone d5 sat at the top of it, and
## the dice kit is what brought it down.
const TARGET := Vector2(4.0, 16.0)


func _initialize() -> void:
	print("\n%-16s %6s %10s %10s" % ["board", "kit", "E[rolls]", "floor"])
	for size in Rules.SIZES:
		var e := _solve(size)
		var names := Array(Rules.kit(size)).map(func(f): return Rules.die_name(f))
		print("%-16s %6s %10.2f %10.2f" % [str(size), " ".join(names), e, _floor(size)])
		if size == Rules.SIZES[0]:
			assert(e >= TARGET.x and e <= TARGET.y,
					"%s takes %.1f rolls, outside the %.0f-%.0f the game is tuned for"
					% [str(size), e, TARGET.x, TARGET.y])
	print("")
	quit()


## Travel with no exact-landing rule: the Manhattan distance over the mean roll of the
## best die in the kit. Everything above this is what the walls cost.
func _floor(size: PackedInt32Array) -> float:
	var best := 0.0
	for faces in Rules.kit(size):
		var mean := 0.0
		for v in faces:
			mean += float(v)
		best = maxf(best, mean / float(faces.size()))
	return float(Board.dist_to_goal(Board.index_to_coords(0, size), size)) / best


## Gauss-Seidel until it stops moving. Sweeping from the cells nearest the goal
## outward means most states are solved in the first pass.
func _solve(size: PackedInt32Array) -> float:
	var n := Board.total_cells(size)
	var goal := n - 1
	var v := PackedFloat64Array()
	v.resize(n)

	var dist := PackedInt32Array()
	dist.resize(n)
	for i in n:
		dist[i] = Board.dist_to_goal(Board.index_to_coords(i, size), size)
	var order := range(n)
	order.sort_custom(func(a, b): return dist[a] < dist[b])

	var kit := Rules.kit(size)
	for _pass in 500:
		var delta := 0.0
		for i in order:
			if i == goal:
				continue
			var c := Board.index_to_coords(i, size)
			var best := INF
			# The player picks the die as well as the move, so the value of a cell is
			# the value of its best die.
			for faces in kit:
				var acc := 0.0
				var stuck := 0
				# Every face is equally likely, and a die may carry the same value twice,
				# so this walks the list rather than a range.
				for roll in faces:
					var moves := Board.legal_moves(c, size, roll)
					if moves.is_empty():
						stuck += 1
						continue
					var cheapest := INF
					for m in moves:
						cheapest = minf(cheapest, v[Board.coords_to_index(m["coords"], size)])
					acc += cheapest
				var n_faces := float(faces.size())
				if stuck == faces.size():
					continue
				# A forfeit is a self-loop: E = (1 + sum of the rest) / (1 - p_stuck).
				var e := (1.0 + acc / n_faces) / (1.0 - float(stuck) / n_faces)
				best = minf(best, e)
			if best == INF:
				continue
			delta = maxf(delta, absf(best - v[i]))
			v[i] = best
		if delta < 1e-9:
			break
	return v[0]
