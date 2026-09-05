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

const CHECKS := ["contests", "stake", "cap", "boss", "run_over", "keys", "draws"]


func _initialize() -> void:
	_contests()
	# add_child() does not run _ready() synchronously from a SceneTree script, so every @onready on Main -- the tray a fight talks to included -- is null until a frame has passed.
	await process_frame
	await _stake()
	await _cap()
	await _boss()
	await _run_over()
	await _keys()
	await _draws()

	for c in CHECKS:
		if not done.has(c):
			push_error("%s did not run to the end -- an assert above failed" % c)
			quit(1)
			return
	print("fight tests ok")
	quit()


## Ties go to the foe in both comparisons -- you have to beat it, not match it.
func _contests() -> void:
	# The contests themselves are covered case by case in tests/test_minigames.gd. What matters here is that a fight drives them at all.
	# One die per dimension of the floor you are standing on.
	# A foe marker has to be tinted for what it is, like every other landing.
	assert(Pal.landing_color("FOE") == Pal.C_FOE)
	assert(Rules.landing(PackedInt32Array([1, 0, 0]), PackedInt32Array([6, 6, 6]), {}, {1: {}}) == "FOE")

	# A die lying on the floor is its own landing, tinted and shaped like every other.
	assert(Pal.landing_color("GIFT") == Pal.C_GIFT)
	assert(Rules.landing(PackedInt32Array([2, 0, 0]), PackedInt32Array([6, 6, 6]), {}, {}, {2: PackedInt32Array([1, 2])}) == "GIFT")
	for faces in Rules.GIFT_DICE:
		assert(Rules.reach(faces) == 1, "a freebie that cannot reach is no way out of anything")

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


## A won die is a gain, full stop. The kit had a cap of one die per axis, and a win over it forced a discard -- which is how a run ends up holding two of the same die and unable to reach the goal at all.
func _cap() -> void:
	var m: Node3D = await _game()
	var full: Array[PackedInt32Array] = []
	for _i in 5:
		full.append(PackedInt32Array([6, 6]))
	m.kit = full
	m.die_index = 0

	m._start_fight(_foe(PackedInt32Array([1, 1]), [0], Rules.OPEN), 0)
	# Two ones against sixes at BIGGER: a win every time.
	m._resolve()
	_read(m)
	assert(m.kit.size() == 6, "the prize did not reach the kit")
	assert(m.fight.is_empty(), "a win asked for something after the cap was removed")
	assert(m.tray.dice[5].visible and not m.tray.dice[6].visible,
			"the tray is not showing exactly the dice the kit holds")

	# The tray is a function of the kit, every refresh. A lost boss round took a die and put the rematch straight up without touching the tray, and the screen showed a die that was already gone.
	var b := _foe(PackedInt32Array([6, 6]), [0, 1, 2], Rules.OPEN)
	b["boss"] = true
	m.kit = _kit([PackedInt32Array([1, 1]), PackedInt32Array([1, 1]), PackedInt32Array([1, 1])])
	m.die_index = 0
	m._start_fight(b, -1)
	for _i in 2:
		m.fight["game"] = 0
		m._resolve()
		_read(m)
	assert(m.kit.size() == 2, "a lost boss match did not cost a die")
	assert(not m.fight.is_empty(), "the rematch did not come back up")
	var shown := 0
	for d in m.tray.dice:
		if d.visible:
			shown += 1
	assert(shown == m.kit.size(),
			"tray shows %d dice, kit holds %d" % [shown, m.kit.size()])
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
	assert(m.games_left() == m.fight["foe"]["games"],
			"a contest was struck off the list after being played")
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
	# A boss takes three rounds and may carry only two contests. The third round used to come up with nothing on offer: no list drawn and SPACE doing nothing, with the fight stuck for good.
	var t: Node3D = await _game()
	t.kit = _kit([PackedInt32Array([1, 2, 3]), PackedInt32Array([1, 2, 3])])
	var two := _foe(PackedInt32Array([3, 4, 4, 5]), [0, 1], Rules.TELL)
	two["boss"] = true
	t._start_fight(two, -1)
	for _i in 4:
		assert(not t.games_left().is_empty(), "a fight with nothing left to pick is a dead end")
		var view: Dictionary = t._fight_view()
		assert(not view["left"].is_empty(), "the screen would have drawn an empty contest list")
		if t.fight["over"] != "":
			break
		t._resolve()
		_read(t)
		if t.fight.is_empty():
			break
	t.free()

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
	# A gift is picked up by landing on it: no fight, no cost, and it leaves the board.
	var g: Node3D = await _game()
	g.kit = _kit([PackedInt32Array([1, 2])])
	var at := 1
	g.gifts = {at: PackedInt32Array([1, 3, 4])}
	g._redraw()
	g.roll = 1
	g.moves = [{"axis": 0, "dir": 1, "coords": PackedInt32Array([1, 0, 0])}]
	g.choose(0)
	await process_frame
	assert(g.kit.size() == 2, "landing on a gift did not add it to the kit")
	assert(g.gifts.is_empty(), "the gift stayed on the board after being taken")
	assert(g.fight.is_empty(), "picking up a die started a fight")
	g.free()

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

	# And the kit is still yours to walk through mid-fight, whoever named the contest: the die you have picked is the die you stake, and walking the kit is how you read what your own dice are.
	var picked: int = m.die_index
	m._cycle_die(1)
	assert(m.die_index != picked, "the kit was locked while the foe held the naming")
	assert(m.notice.begins_with("faces "), "picking a die mid-fight did not say what it is")
	m._cycle_contest(1)
	assert(m.fight["pick"] == 1, "UP/DOWN did not move the highlight")
	var chosen: int = m.games_left()[1]
	m._commit()
	assert(m.fight.is_empty() or chosen >= 0,
			"SPACE committed a contest other than the highlighted one")
	done["keys"] = true
	m.free()


## A fight stops on its result and waits for SPACE. The tests press it, because a result that applies itself in the same frame is the thing that was wrong.
func _read(m: Node3D) -> void:
	if not m.fight.is_empty() and m.fight["over"] != "":
		m._settle()


## A drawn round settles nothing and costs nothing: the contest stands and the dice go again. Handing ties to the foe made every die with repeated faces quietly worse than it looked.
func _draws() -> void:
	var m: Node3D = await _game()
	m.kit = _kit([PackedInt32Array([3, 3])])
	m.die_index = 0
	# Threes against threes at BIGGER: every round is a draw.
	m._start_fight(_foe(PackedInt32Array([3, 3]), [0], Rules.OPEN), 0)
	for _i in 3:
		m._resolve()
		assert(m.fight["over"] == "", "a drawn round settled the fight")
		assert(m.fight["wins"] == 0 and m.fight["losses"] == 0, "a draw was scored")
		assert(m.games_left() == m.fight["foe"]["games"], "a draw changed what is on offer")
		assert(m.kit[0].size() == 2, "a draw cost a die")
		assert(m.fight["last"].ends_with("DRAW, again"), "a draw did not say so")

	# EVEN SUM is only ever offered by a foe whose die is lopsided enough to read. On a balanced die the sum's parity is a coin flip and there is nothing in it to choose.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for _i in 200:
		var f := Rules.make_foe(rng, _i % 3 == 0)
		if f["games"].has(2):
			assert(MG.ALL[2].favours(f["faces"]) >= 0.5,
					"%s offers EVEN SUM as a coin flip" % Rules.die_name(f["faces"]))
	done["draws"] = true
	m.free()


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
