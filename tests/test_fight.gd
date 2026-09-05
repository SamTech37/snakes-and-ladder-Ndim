extends SceneTree

## The fights. Two halves: the contests on hand-built rolls, where nothing is random and a wrong answer is a wrong answer; then the real scene, driven through whole fights so the kit cap, the stake and the boss are checked where they actually live.
##
## Every fight here is started by hand on a board dealt with no foes on it, so nothing depends on where the generator happened to put one.
##
## Run: godot --headless --script tests/test_fight.gd

const Rules = preload("res://src/game/rules.gd")
const MG = preload("res://src/game/minigames.gd")
const Pal = preload("res://src/palette.gd")
const Ghosts = preload("res://src/ghost/ghosts.gd")


## Which checks ran to the end. A failed `assert` does not stop a `--script` run -- it prints, abandons the function it is in, and returns to the caller, so a test can fail and the process still exit 0. Each check signs off when it finishes, and the run fails if a signature is missing.
var done := {}

const CHECKS := ["contests", "stake", "cap", "boss", "run_over", "keys"]


func _initialize() -> void:
	_contests()
	# add_child() does not run _ready() synchronously from a SceneTree script, so every @onready on Main -- the tray a fight talks to included -- is null until a frame has passed.
	await process_frame
	await _stake()
	await _cap()
	await _boss()
	await _run_over()
	await _keys()

	for c in CHECKS:
		if not done.has(c):
			push_error("%s did not run to the end -- an assert above failed" % c)
			quit(1)
			return
	print("fight tests ok")
	quit()


## Ties go to the foe in both comparisons -- you have to beat it, not match it.
func _contests() -> void:
	var bigger: MG.Minigame = MG.ALL[0]
	assert(bigger.play(5, 3))
	assert(not bigger.play(3, 5))
	assert(not bigger.play(4, 4), "a tie is not a win")

	var smaller: MG.Minigame = MG.ALL[1]
	assert(smaller.play(2, 6))
	assert(not smaller.play(6, 2))
	assert(not smaller.play(4, 4), "a tie is not a win")

	var even: MG.Minigame = MG.ALL[2]
	assert(even.play(3, 5), "3 + 5 is even")
	assert(even.play(2, 4))
	assert(not even.play(1, 2))

	# The one place that says which die suits which contest. A big die has to be worth more at BIGGER than a small one, and the other way round at SMALLER -- that opposition is what stops one die from being the answer to everything.
	var big := PackedInt32Array([4, 5, 6])
	var small := PackedInt32Array([1, 2, 3])
	assert(bigger.favours(big) > bigger.favours(small))
	assert(smaller.favours(small) > smaller.favours(big))
	# Certainty is the edge at EVEN SUM, either way round.
	assert(even.favours(PackedInt32Array([2, 4, 6])) > even.favours(PackedInt32Array([1, 2])))

	# One die per dimension of the floor you are standing on.
	assert(Rules.kit_cap(PackedInt32Array([6, 6, 6])) == 3)
	assert(Rules.kit_cap(PackedInt32Array([10, 10])) == 2)

	# A foe marker has to be tinted for what it is, like every other landing.
	assert(Pal.landing_color("FOE") == Pal.C_FOE)
	assert(Rules.landing(PackedInt32Array([1, 0, 0]), PackedInt32Array([6, 6, 6]), {}, {1: {}}) == "FOE")

	# And shaped for it: the marker looks up a child of ghost.tscn by name, so a missing node would only surface as a crash on the turn a foe is one roll away.
	var g = load("res://src/ghost/ghost.tscn").instantiate()
	for kind in Ghosts.SHAPE:
		assert(g.has_node(Ghosts.SHAPE[kind]), "ghost.tscn has no %s shape" % Ghosts.SHAPE[kind])
	g.free()
	done["contests"] = true


## Losing takes the die you staked, not a random one. That is what makes the commit carry the risk as well as the odds.
func _stake() -> void:
	var m: Node3D = await _game()
	m.kit = _kit([PackedInt32Array([1, 2, 3]), PackedInt32Array([1, 2, 3, 4, 5])])
	m.die_index = 1
	var staked: PackedInt32Array = m.die()
	m._start_fight(_foe(PackedInt32Array([6, 6]), [0], Rules.OPEN), 0)
	assert(m.fight["game"] == 0, "an OPEN foe has to name the contest before you commit")
	# Its die is two sixes and the contest is BIGGER, so this is a loss every time.
	m._resolve()
	_read(m)
	assert(m.kit.size() == 1, "a lost fight did not take a die")
	assert(not m.kit.has(staked), "a lost fight took a die that was not the one staked")
	assert(m.fight.is_empty(), "the fight did not end")
	done["stake"] = true
	m.free()


## Over the cap, taking a die means dropping one -- the kit never grows past one die per dimension of the floor.
func _cap() -> void:
	var m: Node3D = await _game()
	var cap: int = Rules.kit_cap(m.size)
	var full: Array[PackedInt32Array] = []
	for _i in cap:
		full.append(PackedInt32Array([6, 6]))
	m.kit = full
	m.die_index = 0

	m._start_fight(_foe(PackedInt32Array([1, 1]), [0], Rules.OPEN), 0)
	# Two ones against sixes at BIGGER: a win every time.
	m._resolve()
	_read(m)
	assert(m.kit.size() == cap + 1, "the prize did not reach the kit")
	assert(m.fight["discard"], "over the cap and nothing was asked to be dropped")
	m._discard(0)
	assert(m.kit.size() == cap, "the kit stayed over its cap")
	assert(m.fight.is_empty(), "the fight did not end after the discard")

	# A win that leaves the kit at the cap asks for nothing.
	m._lose_die(0)
	m._start_fight(_foe(PackedInt32Array([1, 1]), [0], Rules.OPEN), 0)
	m._resolve()
	_read(m)
	assert(m.kit.size() == cap and m.fight.is_empty(), "a win under the cap should not prompt")
	done["cap"] = true
	m.free()


## The boss takes two of three, plays a different contest each round, and losing it does not lock the run: it comes straight back, and each attempt costs a die.
func _boss() -> void:
	var m: Node3D = await _game()
	m.kit = _kit([PackedInt32Array([6, 6]), PackedInt32Array([6, 6]), PackedInt32Array([6, 6])])
	m.die_index = 0
	var boss := _foe(PackedInt32Array([1, 1]), [0, 1, 2], Rules.OPEN)
	boss["boss"] = true
	m._start_fight(boss, -1)
	var first: int = m.fight["game"]
	m._resolve()
	_read(m)
	assert(m.fight["wins"] + m.fight["losses"] == 1, "one round should have resolved")
	assert(m.fight["used"] == [first], "the contest played was not recorded as used")
	assert(m.fight["game"] != first, "the boss repeated a contest it had already played")
	assert(m.kit.size() == 3, "a single boss round should cost nothing yet")
	m.free()

	# Losing the match entirely costs a die and puts the boss straight back up.
	var b: Node3D = await _game()
	b.kit = _kit([PackedInt32Array([1, 1]), PackedInt32Array([1, 1]), PackedInt32Array([1, 1])])
	b.die_index = 0
	var hard := _foe(PackedInt32Array([6, 6]), [0, 1, 2], Rules.OPEN)
	hard["boss"] = true
	b._start_fight(hard, -1)
	# Ones against sixes at BIGGER: every round is a loss, and two of them settle the match. The loop watches the kit rather than the score, because the rematch resets the score the moment the match is lost -- which is the thing being tested.
	var guard := 0
	while b.kit.size() == 3 and guard < 10:
		guard += 1
		b.fight["game"] = 0
		b._resolve()
		_read(b)
	assert(b.kit.size() == 2, "a lost boss match did not cost exactly one die")
	assert(not b.fight.is_empty() and b.fight["wins"] == 0 and b.fight["losses"] == 0,
			"the boss did not come back for a rematch")
	assert(not b.won, "a lost boss should not have won the floor")
	done["boss"] = true
	b.free()


## Your last die cannot be taken, only broken. A run that starts on one die has to survive its first lost fight, or the game is one coin flip long.
func _run_over() -> void:
	var m: Node3D = await _game()
	m.kit = _kit([PackedInt32Array([1, 2, 3, 4, 5])])
	m.die_index = 0
	# Ones against sixes at BIGGER: every one of these is a loss.
	var losses := 0
	while not m.dead and losses < 10:
		losses += 1
		m._start_fight(_foe(PackedInt32Array([6, 6]), [0], Rules.TELL), 0)
		m.fight["game"] = 0
		m._resolve()
		_read(m)
		if not m.dead:
			assert(m.kit.size() == 1, "the last die was taken instead of broken")
			# A d5 wears down to [1,2,3,4], then [1,2,3], then [1,2]: the largest face goes each time, so the die gets safer to travel with and worse to fight with.
			var want := PackedInt32Array()
			for v in range(1, 6 - losses):
				want.append(v)
			assert(m.kit[0] == want, "a broken die came out %s, not %s"
					% [str(m.kit[0]), str(want)])
	assert(losses == 4, "a d5 should survive three lost fights and go on the fourth, not %d" % losses)
	assert(m.kit.is_empty() and m.dead, "a shattered last die did not end the run")
	assert(m.fight.is_empty(), "the fight outlived the run")

	# Holding more than one, the staked die is still taken outright.
	var k: Node3D = await _game()
	k.kit = _kit([PackedInt32Array([1, 2, 3]), PackedInt32Array([1, 2, 3])])
	k.die_index = 0
	k._start_fight(_foe(PackedInt32Array([6, 6]), [0], Rules.OPEN), 0)
	k._resolve()
	_read(k)
	assert(k.kit.size() == 1 and not k.dead, "a lost fight with a spare die should take the die whole")
	assert(k.kit[0].size() == 3, "a die was broken while another was in hand")

	# And a fight always contains a decision: down to one die there is nothing to choose between, so the foe shows its die and the contest becomes yours to name.
	k._start_fight(_foe(PackedInt32Array([6, 6]), [0, 1], Rules.OPEN), 0)
	assert(k.fight["game"] < 0, "an OPEN foe left no decision at all to a player holding one die")
	done["run_over"] = true
	k.free()
	m.free()


## SPACE means one thing -- commit to what is in front of you -- and the number keys belong to the board alone. Choosing a die or a contest is on the arrows.
func _keys() -> void:
	var m: Node3D = await _game()
	m.kit = _kit([PackedInt32Array([1, 2, 3]), PackedInt32Array([1, 2, 3, 4, 5])])
	m.die_index = 0

	# Nothing on the board: SPACE throws.
	m._commit()
	assert(m.roll > 0, "SPACE did not roll")
	var turns: int = m.turns

	# A roll you cannot live with: SPACE again, and it costs a token rather than a turn.
	m.rerolls = 1
	m._commit()
	assert(m.rerolls == 0, "SPACE did not spend a token to reroll")
	assert(m.turns == turns, "a reroll cost a turn")

	# Arrows walk the kit, and they wrap.
	m._cycle_die(1)
	assert(m.die_index == 1, "LEFT/RIGHT did not walk the kit")
	m._cycle_die(1)
	assert(m.die_index == 0, "the kit did not wrap")

	# A TELL foe shows its die and leaves the contest to you: UP/DOWN move the highlight, SPACE commits whatever it is on.
	var foe := _foe(PackedInt32Array([6, 6]), [0, 1], Rules.TELL)
	m._start_fight(foe, 0)
	assert(m.fight["game"] < 0, "a TELL foe should not have named the contest")
	assert(m.fight["pick"] == 0)
	m._cycle_contest(1)
	assert(m.fight["pick"] == 1, "UP/DOWN did not move the highlight")
	var chosen: int = m.games_left()[1]
	m._commit()
	assert(m.fight.is_empty() or m.fight["discard"] or m.fight["used"] == [chosen],
			"SPACE committed a contest other than the highlighted one")
	done["keys"] = true
	m.free()


## A fight stops on its result and waits for SPACE. The tests press it, because a result that applies itself in the same frame is the thing that was wrong.
func _read(m: Node3D) -> void:
	if not m.fight.is_empty() and m.fight["over"] != "":
		m._settle()


func _kit(dice: Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for d in dice:
		out.append(d)
	return out


func _foe(faces: PackedInt32Array, games: Array, order: int) -> Dictionary:
	var g: Array[int] = []
	for x in games:
		g.append(x)
	return {"faces": faces, "games": g, "trait": order, "boss": false}


func _game() -> Node3D:
	var m = load("res://src/main/main.tscn").instantiate()
	m.size = PackedInt32Array([6, 6, 6])
	m.anim = false
	m.foe_count = 0
	m.boss_fight = false
	root.add_child(m)
	await process_frame
	return m
