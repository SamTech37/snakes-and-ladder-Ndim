extends RefCounted

# ponytail: preloaded as `MG` by its users rather than `class_name`, so `--script` runs work without a built global class cache. Same reason as board.gd and rules.gd.

## The contests a fight is decided by. One roll each, one class per game, so adding 對子 / 吹牛 / 猜結果 / 中位數 is a class and an entry in ALL rather than a rewrite.
##
## Nodeless and static like the rest of the rules: a contest has to be resolvable without a scene, because tests/test_fight.gd checks every one of them on hand-built rolls rather than on whatever the dice happened to do.
##
## **Ties go to the foe.** You have to beat it, not match it -- otherwise a d1-ish die with one repeated face would draw its way through the game.


class Minigame extends RefCounted:
	func label() -> String:
		return ""

	## Rolled values in, did *I* win.
	func play(_mine: int, _theirs: int) -> bool:
		return false

	## 0..1: how well this die suits this contest. One place says "a big die is good at BIGGER", so the foe's own choice and any hint the HUD grows cannot disagree.
	func favours(_faces: PackedInt32Array) -> float:
		return 0.5

	## The real chance this die beats that one at this contest, counted rather than guessed: every face against every face, which is a few dozen comparisons on the dice this game holds.
	##
	## This is what the player is shown, because `favours()` is a heuristic with no opponent in it -- printing it as a percentage claims something it does not know. A number on screen that looks like a probability and is not one is worse than no number.
	func odds(mine: PackedInt32Array, theirs: PackedInt32Array) -> float:
		var wins := 0
		for a in mine:
			for b in theirs:
				if play(a, b):
					wins += 1
		return float(wins) / float(maxi(1, mine.size() * theirs.size()))

	## Here rather than beside ALL because an inner class cannot see the outer script's statics -- but it does inherit its own base's.
	static func mean(faces: PackedInt32Array) -> float:
		var acc := 0.0
		for v in faces:
			acc += float(v)
		return acc / float(maxi(1, faces.size()))


## 比大. The one contest where a d6 -- dead weight against a wall -- is the best thing you can be holding.
class Bigger extends Minigame:
	func label() -> String:
		return "BIGGER"

	func play(mine: int, theirs: int) -> bool:
		return mine > theirs

	func favours(faces: PackedInt32Array) -> float:
		return clampf(mean(faces) / 6.0, 0.0, 1.0)


## 比小. The travel-efficient dice win here, which is what stops a small kit from being purely a compromise.
class Smaller extends Minigame:
	func label() -> String:
		return "SMALLER"

	func play(mine: int, theirs: int) -> bool:
		return mine < theirs

	func favours(faces: PackedInt32Array) -> float:
		return clampf(1.0 - mean(faces) / 6.0, 0.0, 1.0)


## 奇偶. The sum decides, so neither die's size matters -- only the parity its faces carry. A die whose faces are all one parity turns this into a read of the foe's. No caller and no tie: the sum is even or it is not.
class EvenSum extends Minigame:
	func label() -> String:
		return "EVEN SUM"

	func play(mine: int, theirs: int) -> bool:
		return (mine + theirs) % 2 == 0

	func favours(faces: PackedInt32Array) -> float:
		var even := 0
		for v in faces:
			if v % 2 == 0:
				even += 1
		# Certainty is the edge here, either way: a die that is always even wins every time the foe rolls even, and always loses when it rolls odd -- which is a contest you can read, unlike a die that is half and half.
		var p := float(even) / float(maxi(1, faces.size()))
		return absf(p - 0.5) * 2.0


## ponytail: static var, not const -- an array of instances is not a constant expression. Indices into this are what a foe carries, so the order is the identity.
static var ALL: Array[Minigame] = [Bigger.new(), Smaller.new(), EvenSum.new()]
