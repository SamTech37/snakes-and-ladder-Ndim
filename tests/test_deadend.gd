extends SceneTree

## The game may never reach a state with nothing to do in it.
##
## Every dead end this project has shipped was found by a person playing, which is the wrong way round: all of them were derivable without playing. A kit of dice that all move in threes cannot land one cell from the goal. A boss best-of-three that struck contests off its own list ran out on the third round. A fight that resolved into no offer and no result sat there for ever.
##
## So this drives whole runs with everything switched on -- foes, gifts, the chaser, the boss -- and after every single step asserts that the player has *something to press*. A run may end (won, or out of dice); it may not stop.
##
## Run: godot --headless --script tests/test_deadend.gd

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")
const MG = preload("res://src/game/minigames.gd")

## Generous for a player who is actually trying: the boards cost 8-10 rolls to cross, plus fights, forfeits and a chaser that keeps starting them.
## A floor has to be finishable. The *run* does not -- it is endless by design, and asserting that one ends measured nothing except how fast the climb outruns the step budget: the first version of this reported a failure at 9D, where the board is 3^9 cells and a floor honestly takes a while.
##
## Steps, not turns: a fight round, a forfeit and a reroll each cost one. Generous for boards that cost 8-10 rolls to cross.
const FLOOR_CAP := 400

## Floors to climb before calling a run proven. Three is two ascents, which is where the kit, the tokens and the chaser have all carried across at least once.
const FLOORS := 3

## A single fight cannot need more than this. Draws replay a round, and a lost boss rematches, but both are bounded by the dice in hand.
const FIGHT_CAP := 200

## Every run has to reach the end of its own loop. One completing does not cover for another abandoning halfway through a failed assert.
var runs := 0
var expected := 0


func _initialize() -> void:
	await process_frame
	# The 2D board is what a run opens on; the 4D one exercises decks, gifts, and a boss with fewer contests than it has rounds.
	for size in [Rules.floor_size(2), Rules.floor_size(4)]:
		for seed in [1, 7]:
			expected += 1
			await _run(size, seed)
	if runs != expected:
		push_error("%d of %d runs finished -- an assert above failed" % [runs, expected])
		quit(1)
		return
	print("dead-end sweep ok")
	quit()


func _run(size: PackedInt32Array, seed: int) -> void:
	var m = load("res://src/main/main.tscn").instantiate()
	m.size = size
	m.anim = false
	root.add_child(m)
	await process_frame
	m.rng.seed = seed
	m.new_game()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var steps := 0
	var fight_steps := 0
	var floor_d: int = m.size.size()

	while true:
		# The budget is per floor, and climbing gives you a fresh one.
		if m.size.size() != floor_d:
			floor_d = m.size.size()
			steps = 0
		steps += 1
		assert(steps < FLOOR_CAP,
				"%s seed %d: playing toward the goal on floor %dD and still not there after %d steps, at %s, %d from home"
				% [str(size), seed, floor_d, FLOOR_CAP, str(m.coords),
				Board.dist_to_goal(m.coords, m.size)])
		if m.floors >= FLOORS:
			break
		_assert_live(m, size, seed)
		if m.dead or m.won:
			break

		if not m.fight.is_empty():
			fight_steps += 1
			assert(fight_steps < FIGHT_CAP,
					"%s seed %d: a fight ran %d rounds without ending" % [str(size), seed, fight_steps])
			_step_fight(m, rng)
			continue
		fight_steps = 0

		if m.roll == 0:
			m.do_roll()
		elif m.moves.is_empty():
			# A roll with nothing legal has to have handed back a token on the way in, or the turn cannot be got out of at all.
			assert(m.rerolls > 0,
					"%s seed %d: nothing legal and no token to roll again" % [str(size), seed])
			m.reroll()
		else:
			# Played to win, not at random. A random walker on a board with a chaser that resets on every catch can wander for ever without that meaning anything is wrong; a player who always steps toward the goal and still cannot finish has found a lock.
			m.choose(_closest(m))
			await process_frame

	m.free()
	runs += 1


## Something to press, always. This is the whole point of the file.
func _assert_live(m, size: PackedInt32Array, seed: int) -> void:
	var where := "%s seed %d floor %dD" % [str(size), seed, m.size.size()]
	if m.dead or m.won:
		return

	# There is a kit, and it can actually get somewhere. A die whose faces share a factor only lands that many steps away, so a whole kit like that cannot finish the board however long it plays.
	assert(not m.kit.is_empty(), "%s: alive with no dice" % where)
	var best := 99
	for faces in m.kit:
		best = mini(best, Rules.reach(faces))
	assert(best == 1, "%s: every die in the kit moves in %ds -- the goal is unreachable" % [where, best])

	if not m.fight.is_empty():
		# Either a result is waiting to be read, or there is a contest to commit to.
		if m.fight["over"] != "":
			return
		assert(not m.games_left().is_empty(), "%s: a fight with no contest on offer" % where)
		var view: Dictionary = m._fight_view()
		assert(not view["left"].is_empty(), "%s: the screen would draw an empty contest list" % where)
		for g in view["left"]:
			assert(g >= 0 and g < MG.ALL.size(), "%s: a contest that does not exist" % where)
		return

	# Out of a fight: a roll to make, a move to pick, or a token to spend.
	if m.roll == 0:
		return
	assert(not m.moves.is_empty() or m.rerolls > 0,
			"%s: rolled %d, nothing legal, no token" % [where, m.roll])


## The legal move that ends up nearest the goal.
func _closest(m) -> int:
	var best := 0
	var best_d := 1 << 30
	for i in m.moves.size():
		var d: int = Board.dist_to_goal(m.moves[i]["coords"], m.size)
		if d < best_d:
			best_d = d
			best = i
	return best


func _step_fight(m, rng: RandomNumberGenerator) -> void:
	if m.fight["over"] != "":
		m._settle()
		return
	if m.fight["game"] < 0:
		var left: Array = m.games_left()
		m.fight["pick"] = rng.randi_range(0, left.size() - 1)
	# Whichever die is picked; the point is that committing always does something.
	if m.kit.size() > 1:
		m._pick_die(rng.randi_range(0, m.kit.size() - 1))
	var before: String = "%s%d%d" % [m.fight["over"], m.fight["wins"], m.fight["losses"]]
	m._commit()
	if not m.fight.is_empty():
		var after: String = "%s%d%d" % [m.fight["over"], m.fight["wins"], m.fight["losses"]]
		# A draw is allowed to leave the score alone, but it must have thrown the dice: the one thing forbidden is a press that changes nothing at all, for ever.
		assert(after != before or m.fight["last"].ends_with("DRAW, again"),
				"committing a fight changed nothing and offered nothing new")
