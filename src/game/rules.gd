extends RefCounted

# ponytail: preloaded as `Rules` by its users rather than `class_name`, so
# `--script` runs work without a built global class cache. Same reason as board.gd.

## What a turn costs and what a cell does to you. Static and nodeless like board.gd:
## the rules have to be measurable without a scene, because tests/odds.gd solves the
## whole game over them.

const Board = preload("res://src/board/board.gd")
const MG = preload("res://src/game/minigames.gd")

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
		foes := {}, gifts := {}) -> String:
	var idx := Board.coords_to_index(cell, size)
	# The goal is where the boss stands, so GOAL already says "a fight is here".
	if idx == Board.total_cells(size) - 1:
		return "GOAL"
	if foes.has(idx):
		return "FOE"
	if gifts.has(idx):
		return "GIFT"
	if not links.has(idx):
		return ""
	var to := Board.index_to_coords(links[idx], size)
	return "LADDER" if Board.dist_to_goal(to, size) < Board.dist_to_goal(cell, size) else "SNAKE"


## How many dice may be shown side by side on the tray. There is **no cap on the kit** -- it was one die per axis, and it turned a run into a forced discard that could leave you holding two of the same locked die. Winning a die is a gain now, and the shape of the kit is the player's business.
const TRAY_DICE := 8


## The board for floor `d`. The run is a climb through dimension counts, so the floor number and the dimension count are the same number. The first four come out of SIZES, which odds.gd and the screenshot harness already measure; past 5D nothing has been looked at, so they are the smallest lattice that still has an interior.
static func floor_size(d: int) -> PackedInt32Array:
	for s in SIZES:
		if s.size() == d:
			return s
	var out := PackedInt32Array()
	for _i in maxi(2, d):
		out.append(3)
	return out


## Every step this die can take, reduced. A die whose faces share a common factor can only ever reach cells that many steps away: [3,3,3] moves 3 and nothing else, so from one cell short of the goal it can never land on it, and no number of rerolls changes that -- every roll is the same 3.
##
## Moves go both ways along an axis, so a gcd of 1 is enough to reach anything: [2,3] gets you one cell by going three forward and two back. That makes this the whole condition, and every die the game can hand out has to satisfy it.
static func reach(faces: PackedInt32Array) -> int:
	var g := 0
	for v in faces:
		g = _gcd(g, v)
	return maxi(1, g)


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


## The fewest faces a die can be ground down to. Below this it is gone: a two-face die is already a coin, and a one-face die makes a forward move legal from every cell but the goal, which deletes the endgame.
const MIN_FACES := 2


## Your last die cannot be taken, only broken: it loses its largest face. That is what stops a single coin flip from ending a run on the first foe — with one die in hand, losing costs you reach rather than everything, and the silhouette on the tray loses a side so you can watch it happening.
## The largest face, because that is the one worth most in BIGGER and the one that overshoots the far wall: the die gets safer to travel with and worse to fight with as it wears down.
static func damaged(faces: PackedInt32Array) -> PackedInt32Array:
	var out := faces.duplicate()
	var worst := 0
	for i in out.size():
		if out[i] >= out[worst]:
			worst = i
	out.remove_at(worst)
	# Losing a face can leave the rest sharing a factor -- [3,3,6] breaks down to [3,3], which can only ever move in threes and cannot land on a goal one cell away. A cracked die gives up a face rather than the run, so the smallest one drops to 1.
	if reach(out) > 1:
		var least := 0
		for i in out.size():
			if out[i] <= out[least]:
				least = i
		out[least] = 1
	return out


## What you set out with: one die. Room to carry more is what ascending buys, so floor one is about using what you have rather than choosing between things.
## The smallest die, and that is measured rather than chosen by taste: alone on the opening board a d3 costs 11.61 rolls against a d6's 13.82, and on [6,6,6] a d3 costs 10.62 against a d5's 13.38. Big faces are dead weight against the far wall, and a lone die has nothing to hide behind. tests/odds.gd prints both columns and asserts this one is the cheaper.
static func start_kit(size: PackedInt32Array) -> Array[PackedInt32Array]:
	var best := kit(size)[0]
	for faces in kit(size):
		if faces.size() < best.size():
			best = faces
	return [best]


## How much a foe tells you before you commit. The 分蛋糕 split: one side frames the contest, the other picks inside it. OPEN -- it names the game, you choose which die to stake. TELL -- it shows its die, you choose which game to hold it in. ponytail: the two blind orders (commit first, learn after) are deliberately not here yet -- they are only a bet once the player knows which die suits which contest.
enum { OPEN, TELL }

## Foe dice, as face lists. Not capped to the board: a foe never has to travel, so an oversized face costs it nothing, and it is exactly what makes its die a bad prize.
static var FOE_DICE: Array[PackedInt32Array] = [
	PackedInt32Array([1, 2, 3]),
	PackedInt32Array([1, 2, 3, 4, 5]),
	PackedInt32Array([1, 1, 5, 5]),
	PackedInt32Array([1, 3, 3]),
	PackedInt32Array([2, 2, 4, 5]),
	PackedInt32Array([1, 3, 5, 5]),
]

## What a boss brings. Bigger and stranger than anything on the floor, because it is the one fight you cannot walk around.
static var BOSS_DICE: Array[PackedInt32Array] = [
	PackedInt32Array([2, 4, 5, 6]),
	PackedInt32Array([1, 1, 6, 6]),
	PackedInt32Array([3, 4, 4, 5]),
]


## Dice lying on the floor, free to whoever lands on them. Plain and small: a gift is a way out of a kit that cannot reach, not a prize, and the interesting dice are still the ones you have to win.
##
## Every one of them reaches everywhere on its own (`reach() == 1`), because the whole point of a freebie is to unstick a run.
static var GIFT_DICE: Array[PackedInt32Array] = [
	PackedInt32Array([1, 2]),
	PackedInt32Array([1, 2, 3]),
	PackedInt32Array([1, 1, 2]),
	PackedInt32Array([1, 3, 4]),
]


static func make_gift(rng: RandomNumberGenerator) -> PackedInt32Array:
	return GIFT_DICE[rng.randi_range(0, GIFT_DICE.size() - 1)]


## A foe as plain data: its die, the contests it knows, and how much it tells you. A Dictionary rather than a class for the same reason `links` is one -- it is data the turn loop passes around, and nothing about it needs behaviour of its own.
static func make_foe(rng: RandomNumberGenerator, boss := false, strong := false) -> Dictionary:
	var pool := BOSS_DICE if boss or strong else FOE_DICE
	var faces: PackedInt32Array = pool[rng.randi_range(0, pool.size() - 1)]
	var games: Array[int] = [0, 1]
	# The parity pair only from a foe whose die is lopsided enough to read. On a balanced die either call is a coin flip with nothing in it to reason about, and a contest you cannot reason about is not a choice. They come as a pair because the call is the decision: one of them alone is a side you were assigned rather than one you took.
	if MG.ALL[2].favours(faces) >= 0.5:
		games.append(2)
		games.append(3)
	if not boss:
		# A floor foe knows two of what it has, so which contest it can reach for is part of what you read off it.
		games.shuffle()
		games = games.slice(0, 3 if games.size() > 2 else 2)
	return {
		"faces": faces,
		"games": games,
		# A boss always names the contest: the last thing it hands you is the choice of which die to lose.
		"trait": OPEN if boss or rng.randi() % 2 == 0 else TELL,
		"boss": boss,
	}
