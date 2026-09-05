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

	## Neither side satisfied the condition. A drawn round is thrown again rather than handed to the foe: losing a die because you matched it is not a result anybody reads as fair.
	func draw(_mine: int, _theirs: int) -> bool:
		return false

	## 0..1: how well this die suits this contest. One place says "a big die is good at BIGGER", so the foe's own choice and any hint the HUD grows cannot disagree.
	func favours(_faces: PackedInt32Array) -> float:
		return 0.5

	## How lopsided a die's parity is: 0 for an even split, 1 for a die that is always odd or always even. Certainty is the edge in a parity call, whichever way it points -- a die that is always even wins every time the foe rolls even and loses every time it rolls odd, which is a contest you can read, unlike one that is half and half.
	static func skew(faces: PackedInt32Array) -> float:
		var even := 0
		for v in faces:
			if v % 2 == 0:
				even += 1
		return absf(float(even) / float(maxi(1, faces.size())) - 0.5) * 2.0

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

	func draw(mine: int, theirs: int) -> bool:
		return mine == theirs

	func favours(faces: PackedInt32Array) -> float:
		return clampf(mean(faces) / 6.0, 0.0, 1.0)


## 比小. The travel-efficient dice win here, which is what stops a small kit from being purely a compromise.
class Smaller extends Minigame:
	func label() -> String:
		return "SMALLER"

	func play(mine: int, theirs: int) -> bool:
		return mine < theirs

	func draw(mine: int, theirs: int) -> bool:
		return mine == theirs

	func favours(faces: PackedInt32Array) -> float:
		return clampf(1.0 - mean(faces) / 6.0, 0.0, 1.0)


## 奇偶, and it takes a caller. The sum decides, so neither die's size matters -- only the parity its faces carry -- but somebody has to say which parity they are betting on, or one side is silently assigned even and a 2 against a 3 reads as a cheat rather than a loss.
##
## So the call is the contest: ODD SUM and EVEN SUM are two entries in the list and picking one is picking a side. Against a die that is mostly even, bet odd with an odd die; the read is the whole game here.
##
## Against a balanced spread there is nothing to read and both are coin flips, so `Rules.make_foe()` only offers the pair when its own die is lopsided enough to reason about. No draw is possible: a sum is even or it is not.
class EvenSum extends Minigame:
	func label() -> String:
		return "EVEN SUM"

	func play(mine: int, theirs: int) -> bool:
		return (mine + theirs) % 2 == 0

	func favours(faces: PackedInt32Array) -> float:
		return skew(faces)


class OddSum extends Minigame:
	func label() -> String:
		return "ODD SUM"

	func play(mine: int, theirs: int) -> bool:
		return (mine + theirs) % 2 == 1

	func favours(faces: PackedInt32Array) -> float:
		return skew(faces)


## ponytail: static var, not const -- an array of instances is not a constant expression. Indices into this are what a foe carries, so the order is the identity.
static var ALL: Array[Minigame] = [Bigger.new(), Smaller.new(), EvenSum.new(), OddSum.new()]
