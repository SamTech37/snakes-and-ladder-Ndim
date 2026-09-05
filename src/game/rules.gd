extends RefCounted

# ponytail: preloaded as `Rules` by its users rather than `class_name`, so
# `--script` runs work without a built global class cache. Same reason as board.gd.

## What a turn costs and what a cell does to you. Static and nodeless like board.gd:
## the rules have to be measurable without a scene, because tests/odds.gd solves the
## whole game over them.

const Board = preload("res://src/board/board.gd")

## Boards D cycles through, so the higher-dimensional ones are reachable from inside
## the game rather than only by editing the export or a test script.
## ponytail: static var, not const -- PackedInt32Array literals are not constant
## expressions, so a const array of them will not parse.
## [6,6,6] stays first: tests/odds.gd holds that one to a target band, and it is the
## board the game opens on.
static var SIZES: Array[PackedInt32Array] = [
	PackedInt32Array([6, 6, 6]),
	PackedInt32Array([4, 4, 4, 4]),
	PackedInt32Array([3, 3, 3, 3, 3]),
	# 2D: one plane, no deck to explode, so TAB only widens the spacing. It is the
	# board everyone already knows, and it is the one place the projection cannot be
	# blamed for anything.
	PackedInt32Array([10, 10]),
]

## The dice the player picks between before rolling. Measured on [6,6,6]: a single d5
## costs 13.4 rolls under optimal play and picking between d6 and d3 costs 9.4, which
## beats every rule-level fix for the exact-landing endgame (declining a turn 10.4,
## bouncing off the wall 10.4) and is a decision rather than a rule.
##
## ponytail: no d1. With a d1 a forward move is legal from every cell but the goal, so
## it deletes the endgame, the forfeits and every reroll the player could earn -- it is
## something to unlock, not something to hand over at the start.
const DICE := [6, 3]


## The starting kit on this board, capped and deduplicated. On a 4-wide lattice both
## dice cap to 3, and offering the same die twice is noise.
static func kit(size: PackedInt32Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for d in DICE:
		var f := faces_for(d, size)
		if not out.has(f):
			out.append(f)
	return out


## A plain die as a list of faces: 1..n, capped to what this board can use. A die is a
## list rather than a count because a die won off a foe need not be plain -- [1,1,5,5]
## is streaky and [3,3,3] is certain, and both have to roll through the same code.
static func faces_for(die: int, size: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in range(1, die_faces(die, size) + 1):
		out.append(v)
	return out


## What to call a die. Plain 1..n is "d5"; anything else is spelled out, because a
## count would be a lie about a die whose faces are not 1..n.
## ponytail: no separator -- every face on a playable board is a single digit, and the
## silhouette already counts the sides. Revisit if a face ever goes above 9.
static func die_name(faces: PackedInt32Array) -> String:
	for i in faces.size():
		if faces[i] != i + 1:
			return "".join(Array(faces).map(func(v): return str(v)))
	return "d%d" % faces.size()


## True when this roll traps the player: nothing legal, one forced move, or nothing
## that gets closer to the goal. Granting the token on the same roll that traps you is
## what keeps a losing move from ever being mandatory -- you always hold one when it
## matters, so no separate "decline" rule is needed.
static func grants_reroll(moves: Array, from: PackedInt32Array, size: PackedInt32Array) -> bool:
	if moves.size() <= 1:
		return true
	var d := Board.dist_to_goal(from, size)
	for m in moves:
		if Board.dist_to_goal(m["coords"], size) < d:
			return false
	return true


## d6 on a board wide enough for it. An axis of extent 5 can only ever be crossed in
## steps of 1..4, so a 5 or a 6 there would be a guaranteed forfeit.
static func die_faces(die: int, size: PackedInt32Array) -> int:
	var f := 1
	for s in size:
		f = maxi(f, s - 1)
	return mini(f, die)


## What landing on `cell` does: "" for plain floor. One source for the marker's color,
## its shape and the word in the move list, so the three cannot drift apart.
## ponytail: events and foes are not designed yet -- add their case here, and their
## color to the palette, when they exist.
static func landing(cell: PackedInt32Array, size: PackedInt32Array, links: Dictionary) -> String:
	var idx := Board.coords_to_index(cell, size)
	if idx == Board.total_cells(size) - 1:
		return "GOAL"
	if not links.has(idx):
		return ""
	var to := Board.index_to_coords(links[idx], size)
	return "LADDER" if Board.dist_to_goal(to, size) < Board.dist_to_goal(cell, size) else "SNAKE"
