extends SceneTree

## Every contest, case by case, on hand-written rolls. Nothing random, no scene, no dice: a wrong answer here is a wrong answer, and it is the one file to add to when a contest is added.
##
## It exists because EVEN SUM shipped deciding a fight the player had never been asked about -- 2 against 3 is an odd sum and a loss, which is exactly what the rule said and nothing like what the screen promised. The rules were right and untested; the reading of them was wrong.
##
## Run: godot --headless --script tests/test_minigames.gd

const MG = preload("res://src/game/minigames.gd")
const Rules = preload("res://src/game/rules.gd")

var done := {}

const CHECKS := ["cases", "exhaustive", "favours", "labels", "reach"]


func _initialize() -> void:
	_cases()
	_exhaustive()
	_favours()
	_labels()
	_reach()
	for c in CHECKS:
		if not done.has(c):
			push_error("%s did not run to the end -- an assert above failed" % c)
			quit(1)
			return
	print("minigame tests ok")
	quit()


## One table per contest: [my roll, their roll, do I win, is it a draw].
func _cases() -> void:
	var table := {
		"BIGGER": [
			[6, 1, true, false], [2, 1, true, false],
			[1, 6, false, false], [1, 2, false, false],
			[3, 3, false, true], [1, 1, false, true], [6, 6, false, true],
		],
		"SMALLER": [
			[1, 6, true, false], [1, 2, true, false],
			[6, 1, false, false], [2, 1, false, false],
			[3, 3, false, true], [1, 1, false, true], [6, 6, false, true],
		],
		# The pair that has to be a call rather than an assignment. 2 and 3 sum to 5: odd, so ODD SUM takes it and EVEN SUM does not -- and the player picked which of those they were betting on.
		"EVEN SUM": [
			[2, 4, true, false], [1, 3, true, false], [3, 3, true, false], [6, 6, true, false],
			[2, 3, false, false], [1, 2, false, false], [5, 6, false, false],
		],
		"ODD SUM": [
			[2, 3, true, false], [1, 2, true, false], [5, 6, true, false],
			[2, 4, false, false], [1, 3, false, false], [3, 3, false, false], [6, 6, false, false],
		],
	}
	for g in MG.ALL:
		var label: String = g.label()
		assert(table.has(label), "%s has no cases -- add them here with the contest" % label)
		for row in table[label]:
			var mine: int = row[0]
			var theirs: int = row[1]
			assert(g.play(mine, theirs) == row[2],
					"%s: %d v %d should %s" % [label, mine, theirs, "win" if row[2] else "lose"])
			assert(g.draw(mine, theirs) == row[3],
					"%s: %d v %d should %s be a draw" % [label, mine, theirs, "" if row[3] else "not"])
	done["cases"] = true


## Over every pair of rolls a die in this game can produce: a round is a win, a loss or a draw, never two of those and never none. And the parity pair has to be exactly opposite, or one of the two calls is dead.
func _exhaustive() -> void:
	for g in MG.ALL:
		for a in range(1, 10):
			for b in range(1, 10):
				var win: bool = g.play(a, b)
				var tie: bool = g.draw(a, b)
				assert(not (win and tie),
						"%s: %d v %d is a win and a draw at once" % [g.label(), a, b])

	var even: MG.Minigame = MG.ALL[2]
	var odd: MG.Minigame = MG.ALL[3]
	assert(even.label() == "EVEN SUM" and odd.label() == "ODD SUM",
			"the parity pair moved -- Rules.make_foe() offers them by index")
	for a in range(1, 10):
		for b in range(1, 10):
			assert(even.play(a, b) != odd.play(a, b),
					"%d v %d goes the same way for both parity calls" % [a, b])
			assert(not even.draw(a, b) and not odd.draw(a, b),
					"a sum is even or it is not -- there is no draw in it")

	# BIGGER and SMALLER are opposite everywhere they are not a draw.
	var bigger: MG.Minigame = MG.ALL[0]
	var smaller: MG.Minigame = MG.ALL[1]
	for a in range(1, 10):
		for b in range(1, 10):
			if a == b:
				continue
			assert(bigger.play(a, b) != smaller.play(a, b),
					"%d v %d goes the same way for BIGGER and SMALLER" % [a, b])
	done["exhaustive"] = true


## What the foe reaches for, and the one place that says which die suits which contest. A big die has to be worth more at BIGGER than a small one and the other way round at SMALLER; that opposition is what stops one die being the answer to everything.
func _favours() -> void:
	var big := PackedInt32Array([4, 5, 6])
	var small := PackedInt32Array([1, 2, 3])
	assert(MG.ALL[0].favours(big) > MG.ALL[0].favours(small))
	assert(MG.ALL[1].favours(small) > MG.ALL[1].favours(big))

	# Certainty is the edge in a parity call, whichever way it points, and both calls read the die the same way -- the die's skew is what makes the pair worth offering at all.
	var lopsided := PackedInt32Array([2, 4, 6])
	var balanced := PackedInt32Array([1, 2, 3, 4])
	for g in [MG.ALL[2], MG.ALL[3]]:
		assert(g.favours(lopsided) > g.favours(balanced))
		assert(is_equal_approx(g.favours(lopsided), 1.0), "an all-even die is a certainty")
		assert(is_zero_approx(g.favours(balanced)), "an even split has nothing to read")

	# And a foe only ever offers the parity pair when its die carries that skew.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 300:
		var f := Rules.make_foe(rng, i % 3 == 0)
		var parity: bool = f["games"].has(2) or f["games"].has(3)
		assert(not parity or MG.ALL[2].favours(f["faces"]) >= 0.5,
				"%s offers a parity call that is a coin flip" % Rules.die_name(f["faces"]))
		for g in f["games"]:
			assert(g >= 0 and g < MG.ALL.size(), "foe carries a contest that does not exist")
	done["favours"] = true


## No die the game can hand out may be locked. A die whose faces share a factor can only reach cells that many steps away -- [3,3,3] moves in threes and nothing else, so one cell short of the goal it can never land, and every reroll comes up 3 again. Moves go both ways along an axis, so a gcd of 1 is the whole condition.
func _reach() -> void:
	var pools := {"FOE_DICE": Rules.FOE_DICE, "BOSS_DICE": Rules.BOSS_DICE,
			"GIFT_DICE": Rules.GIFT_DICE}
	for name in pools:
		for faces in pools[name]:
			assert(Rules.reach(faces) == 1,
					"%s carries %s, which can only ever move in %ds"
					% [name, Rules.die_name(faces), Rules.reach(faces)])
	for size in Rules.SIZES:
		for faces in Rules.kit(size):
			assert(Rules.reach(faces) == 1, "the starting kit on %s cannot reach" % str(size))

	assert(Rules.reach(PackedInt32Array([3, 3, 3])) == 3, "the locked die is not being spotted")
	assert(Rules.reach(PackedInt32Array([2, 4])) == 2)
	assert(Rules.reach(PackedInt32Array([2, 3])) == 1, "two and three reach everywhere between them")

	# And a die worn down by lost fights stays able to reach, all the way to the bottom.
	for faces in Rules.FOE_DICE + Rules.BOSS_DICE + Rules.GIFT_DICE:
		var d := faces
		var guard := 0
		while d.size() > Rules.MIN_FACES and guard < 12:
			guard += 1
			d = Rules.damaged(d)
			assert(Rules.reach(d) == 1,
					"%s breaks down to %s, which can only move in %ds"
					% [Rules.die_name(faces), Rules.die_name(d), Rules.reach(d)])
	done["reach"] = true


## Labels are what the player picks by, so they have to be distinct and non-empty.
func _labels() -> void:
	var seen := {}
	for g in MG.ALL:
		var label: String = g.label()
		assert(not label.is_empty(), "a contest with no name cannot be picked")
		assert(not seen.has(label), "two contests both called %s" % label)
		seen[label] = true
	done["labels"] = true
