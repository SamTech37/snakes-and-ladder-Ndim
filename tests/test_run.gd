extends SceneTree

## The run: the chaser that makes time cost something, and the climb from one dimension to the next.
##
## Run: godot --headless --script tests/test_run.gd

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")

## A failed `assert` does not stop a `--script` run -- it prints, abandons the function it is in, and returns to the caller, so a test can fail and the process still exit 0. Each check signs off when it finishes, and the run fails if a signature is missing.
var done := {}

const CHECKS := ["chase", "catch", "climb", "tokens"]


func _initialize() -> void:
	await process_frame
	await _chase()
	await _catch()
	await _climb()
	await _tokens()
	for c in CHECKS:
		if not done.has(c):
			push_error("%s did not run to the end -- an assert above failed" % c)
			quit(1)
			return
	print("run tests ok")
	quit()


## It closes, every roll, and it never wanders: the step it takes is the step it said it would take.
func _chase() -> void:
	var m: Node3D = await _game()
	var d: int = m.roamer_dist()
	assert(d > 0, "the chaser started on top of the player")
	while d > 0:
		var promised: PackedInt32Array = m._roamer_next()
		m._step_roamer()
		assert(m.roamer == promised, "the chaser did not take the step it drew")
		var now: int = m.roamer_dist()
		assert(now < d, "the chaser did not close: %d then %d" % [d, now])
		d = now
	done["chase"] = true
	m.free()


## It moves after you move -- never between your roll and your move, which would take you on a move you had not made yet. A spent token moves it too, because that is a turn's time bought and no ground covered.
func _catch() -> void:
	var m: Node3D = await _game()

	# Rolling is not moving: the chaser holds still until the move is actually made.
	var parked: PackedInt32Array = m.roamer.duplicate()
	m.do_roll()
	assert(m.roamer == parked, "the chaser moved on the roll, before the move was made")
	assert(not m.moves.is_empty(), "no legal move to test the order with")
	m.choose(0)
	await process_frame
	assert(m.roamer != parked, "the chaser did not move after the move was made")
	m.free()

	var r: Node3D = await _game()
	r.rerolls = 1
	r.roll = 1
	var before: PackedInt32Array = r.roamer.duplicate()
	r.reroll()
	assert(r.roamer != before, "a reroll did not advance the chaser")
	assert(r.rerolls == 0, "a reroll did not spend its token")
	r.free()

	var c: Node3D = await _game()
	# One cell away and one roll from the player, so the next step lands on them.
	c.roamer = c.coords.duplicate()
	c.roamer[0] += 1
	c._step_roamer()
	assert(c.roamer == c.coords or not c.fight.is_empty(), "the chaser walked through the player")
	assert(not c.fight.is_empty(), "being caught did not start a fight")
	assert(c.fight["cell"] == c.ROAMER_CELL, "the catch was not marked as the chaser's fight")
	# Whatever happens next, it backs off: left standing on you it would pick a fight on every roll from here to the goal.
	c._end_fight()
	assert(c.roamer_dist() > 0, "the chaser stayed on top of the player after the fight")
	done["catch"] = true
	c.free()


## Beating the boss climbs a dimension and keeps everything the run has won.
func _climb() -> void:
	var m: Node3D = await _game()
	m.kit = _kit([PackedInt32Array([6, 6]), PackedInt32Array([6, 6])])
	m.die_index = 0
	m.boss_fight = true
	var before: int = m.size.size()
	var boss := {"faces": PackedInt32Array([1, 1]), "games": [0, 1, 2] as Array[int],
			"trait": Rules.OPEN, "boss": true}
	m._start_fight(boss, -1)
	# Sixes against ones at BIGGER, twice: the match, and the floor.
	for _i in 2:
		m.fight["game"] = 0
		m._resolve()
		_read(m)
	assert(m.size.size() == before + 1, "beating the boss did not climb a dimension")
	assert(m.size == Rules.floor_size(before + 1), "the next floor is not the board for that dimension")
	assert(m.kit.size() == 2, "the kit did not survive the climb")
	assert(m.floors == 1, "the floor was not counted")
	assert(not m.won, "the run should carry on rather than end at a cleared floor")
	assert(m.roamer_dist() > 0, "the new floor started with the chaser on top of the player")
	done["climb"] = true
	m.free()


## Whether a stockpile of tokens survives a floor is the thing to watch, so it is a flag, and it has to actually do something in both positions.
func _tokens() -> void:
	for carry in [true, false]:
		var m: Node3D = await _game()
		m.carry_tokens = carry
		m.rerolls = 3
		m.size = Rules.floor_size(m.size.size() + 1)
		m.new_game(true)
		assert(m.rerolls == (3 if carry else 0),
				"carry_tokens = %s left %d tokens" % [carry, m.rerolls])
		m.free()

	# And a fresh run starts with one die, whatever the last one ended holding.
	var f: Node3D = await _game()
	f.kit = _kit([PackedInt32Array([1, 2]), PackedInt32Array([1, 2]), PackedInt32Array([1, 2])])
	f.new_game()
	assert(f.kit.size() == 1, "a new run did not start on a single die")
	assert(f.kit == Rules.start_kit(f.size), "a new run started on a die odds.gd has not measured")
	assert(f.floors == 0, "a new run kept the last one's floors")
	done["tokens"] = true
	f.free()


## A fight stops on its result and waits for SPACE before anything is applied.
func _read(m: Node3D) -> void:
	if not m.fight.is_empty() and m.fight["over"] != "":
		m._settle()


func _kit(dice: Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for d in dice:
		out.append(d)
	return out


## The opening floor with nothing standing on it: every foe here is placed by hand, so nothing depends on where the generator put one.
func _game() -> Node3D:
	var m = load("res://src/main/main.tscn").instantiate()
	m.size = Rules.floor_size(2)
	m.anim = false
	m.foe_count = 0
	m.boss_fight = false
	root.add_child(m)
	await process_frame
	return m
