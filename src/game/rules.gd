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


## The starting kit on this board, capped and deduplicated. On a 4-wide lattice both dice cap to 3, and offering the same die twice is noise.
static func kit(size: PackedInt32Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for d in DICE:
		var f := faces_for(d, size)
		if not out.has(f):
			out.append(f)
	return out


## A plain die as a list of faces: 1..n, capped to what this board can use. A die is a list rather than a count because a die won off a foe need not be plain -- [1,1,5,5] is streaky and [3,3,3] is certain, and both have to roll through the same code.
static func faces_for(die: int, size: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in range(1, die_faces(die, size) + 1):
		out.append(v)
	return out


## What to call a die. Plain 1..n is "d5"; anything else is spelled out, because a count would be a lie about a die whose faces are not 1..n.
## ponytail: no separator -- every face on a playable board is a single digit, and the silhouette already counts the sides. Revisit if a face ever goes above 9.
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
## `foes` is optional because a caller that has no foes to show -- a test measuring the lattice, say -- should not have to invent an empty one.
static func landing(cell: PackedInt32Array, size: PackedInt32Array, links: Dictionary,
		foes := {}) -> String:
	var idx := Board.coords_to_index(cell, size)
	# The goal is where the boss stands, so GOAL already says "a fight is here".
	if idx == Board.total_cells(size) - 1:
		return "GOAL"
	if foes.has(idx):
		return "FOE"
	if not links.has(idx):
		return ""
	var to := Board.index_to_coords(links[idx], size)
	return "LADDER" if Board.dist_to_goal(to, size) < Board.dist_to_goal(cell, size) else "SNAKE"


## How many dice you may hold: one per dimension of the floor you are standing on. The cap is the whole cost of winning a die -- over it, taking one means dropping one.
static func kit_cap(size: PackedInt32Array) -> int:
	return size.size()


## How much a foe tells you before you commit. The 分蛋糕 split: one side frames the contest, the other picks inside it. OPEN -- it names the game, you choose which die to stake. TELL -- it shows its die, you choose which game to hold it in. ponytail: the two blind orders (commit first, learn after) are deliberately not here yet -- they are only a bet once the player knows which die suits which contest.
enum { OPEN, TELL }

## Foe dice, as face lists. Not capped to the board: a foe never has to travel, so an oversized face costs it nothing, and it is exactly what makes its die a bad prize.
static var FOE_DICE: Array[PackedInt32Array] = [
	PackedInt32Array([1, 2, 3]),
	PackedInt32Array([1, 2, 3, 4, 5]),
	PackedInt32Array([1, 1, 5, 5]),
	PackedInt32Array([3, 3, 3]),
	PackedInt32Array([2, 2, 4, 6]),
	PackedInt32Array([1, 3, 5, 5]),
]

## What a boss brings. Bigger and stranger than anything on the floor, because it is the one fight you cannot walk around.
static var BOSS_DICE: Array[PackedInt32Array] = [
	PackedInt32Array([2, 4, 6, 6]),
	PackedInt32Array([1, 1, 6, 6]),
	PackedInt32Array([4, 4, 4, 4]),
]


## A foe as plain data: its die, the contests it knows, and how much it tells you. A Dictionary rather than a class for the same reason `links` is one -- it is data the turn loop passes around, and nothing about it needs behaviour of its own.
static func make_foe(rng: RandomNumberGenerator, boss := false) -> Dictionary:
	var pool := BOSS_DICE if boss else FOE_DICE
	var games: Array[int] = [0, 1, 2]
	if not boss:
		# A floor foe knows two of the three, so which contest it can reach for is part of what you read off it.
		games.shuffle()
		games = games.slice(0, 2)
	return {
		"faces": pool[rng.randi_range(0, pool.size() - 1)],
		"games": games,
		# A boss always names the contest: the last thing it hands you is the choice of which die to lose.
		"trait": OPEN if boss or rng.randi() % 2 == 0 else TELL,
		"boss": boss,
	}
