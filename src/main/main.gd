extends Node3D

## N-dimensional Snakes & Ladders. Roll gives distance, you pick the axis.
##
## This is the turn loop and the input map, and nothing else. The board's geometry is
## `Board/board_view.gd`, the camera is `CamRig/cam_rig.gd`, the markers are
## `Ghosts/ghosts.gd`, the text is `HUD/hud.gd`, and the rules that can be measured
## without a scene are `src/game/rules.gd`. Nodes and materials live in main.tscn.

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")
const MG = preload("res://src/game/minigames.gd")

enum View { SPREAD, FOCUS }

## How far behind you the chaser is put at the start of a floor, and again after every fight with it. Cells, not turns: it walks one cell per roll, so this is also roughly how many rolls of grace you get.
const HEAD_START := 5

## The chaser is not standing on any cell in `foes` -- it carries its cell with it -- so a fight with it is marked with this instead of an index.
const ROAMER_CELL := -2

## The floor you are standing on. Dimension count and floor number are the same thing: the run opens on the 2D board everybody already knows and climbs from there.
@export var size := PackedInt32Array([10, 10])
@export var link_count := 18
## Manhattan cap on a link's reach. Uncapped endpoints gave full-width lines that
## crossed everything and skipped most of the board in one move.
@export var link_span := 5
## Foes standing on the floor. Off (0) leaves a board with nothing to fight on the way, which is how test_play.gd keeps measuring that a random walk still reaches the goal.
@export var foe_count := 5
## Dice lying on the floor, free to pick up. They exist because a kit can end up unable to reach the goal at all, and because a board with nothing good on it is a board you only ever cross.
@export var gift_count := 3
## The boss on the goal cell. Off means reaching the goal wins outright.
@export var boss_fight := true
## The chaser. It is the clock: travel is otherwise free, and a floor with no clock is won by anyone patient enough.
@export var roamer_on := true
## Whether reroll tokens survive a floor. On, a stockpile carries into every later floor and may well trivialise the endgame stall -- which is exactly the thing to watch, so it is a flag to play both ways rather than a decision made in advance.
@export var carry_tokens := true
## Off makes every hop instant, so test_play.gd can run games without waiting on tweens.
@export var anim := true

@onready var rig: Node3D = $CamRig
@onready var view3d: Node3D = $Board
@onready var ghosts: Node3D = $Ghosts
@onready var player: MeshInstance3D = $Player
@onready var roamer_node: MeshInstance3D = $Roamer
@onready var hud: CanvasLayer = $HUD
@onready var tray: Node3D = $CamRig/Camera3D/Tray

var coords := PackedInt32Array()
var links := {}

## cell index -> foe. A foe leaves its cell once it has been fought, won or lost.
var foes := {}

## cell index -> a die lying there, free to whoever lands on it. The way out of a kit that cannot reach: every gift die reaches everywhere on its own.
var gifts := {}

## The foe standing on the goal. Best of three, and the only fight on the floor you cannot walk around.
var boss := {}

## The fight in progress, empty between them. A Dictionary rather than a class for the same reason a foe is one: the turn loop owns the state, and the fight is a state the turn is in rather than an object with a life of its own.
var fight := {}

## No dice left. The run is over -- there is nothing to roll and nothing to stake.
var dead := false

## The chaser's cell, and the foe it fights as. It steps one cell after every roll, rerolls included, so the escape hatch costs distance and the endgame stall against the far wall is the most dangerous place on the board rather than merely the slowest.
var roamer := PackedInt32Array()
var roamer_foe := {}

## What just happened, in words, until the next roll. A fight that ends in silence leaves you looking at a tray with one fewer die on it and no idea why.
var notice := ""

## Floors cleared this run. The board says which dimension you are on; this says how far you got, which is the only score there is.
var floors := 0

var roll := 0
var moves := []
var turns := 0
var busy := false
var won := false
var view := View.FOCUS
var rng := RandomNumberGenerator.new()

## Where the camera was left in FOCUS, so TAB-ing back returns to the angle you were
## using rather than snapping to the default. SPREAD is deliberately not remembered.
var parked := {}

## The dice held. Each die is its list of face values, not a face count: a won die can read [1,1,5,5], which is streaky, or [3,3,3], which is certain. Run state rather than something derived from `size`, because dice are won and lost and have to outlive the board they were picked up on.
var kit: Array[PackedInt32Array] = []

## Which die in `kit` the next roll uses. A big die is dead weight against a wall --
## picking the small one is how the endgame is played rather than endured.
var die_index := 0

## Spent with X to roll again without spending a turn. Earned on any roll that traps
## you, so the compensation arrives exactly when the wall does.
var rerolls := 0

var dragging := false
var panning := false

## Where the left button went down, so a click can be told from a drag: the same
## button orbits the camera and picks up a die.
var press_at := Vector2.ZERO


func _ready() -> void:
	# Everything each part needs from another is wired here, once, rather than left to
	# scripts reaching up through the tree for their neighbours.
	view3d.rig = rig
	rig.board = view3d
	rig.hud = hud
	ghosts.board = view3d
	view3d.fx = anim
	tray.anim = anim

	# SNL_SEED pins the board so two runs render the same thing — without it a
	# screenshot can't be compared against the one before it.
	var s := OS.get_environment("SNL_SEED")
	if s.is_empty():
		rng.randomize()
	else:
		rng.seed = s.to_int()
	new_game()

	# The fit frames the board below the HUD text, and a Control has no real size until it has been laid out -- at _ready() the status line claims a few hundred pixels of height it does not have, so the opening view is framed for a text bar five times too tall. It looked like the game simply did not start centred, and pressing C to "recentre" was really the first honest fit.
	await get_tree().process_frame
	rig.fit()
	# And the framing follows the window from here on. The wheel zoom is lost on a resize, which is what a refit means and what a resize is asking for.
	get_viewport().size_changed.connect(rig.fit)


## Deals a floor. `keep` carries the run across it: the kit is what a run *is*, so ascending must not re-deal it, while SHIFT+R must.
func new_game(keep := false) -> void:
	coords = Board.index_to_coords(0, size)
	links = Board.gen_links(size, link_count, rng, link_span)
	foes = {}
	var foe_cells := Board.gen_foes(size, foe_count, rng, links)
	for c in foe_cells:
		foes[c] = Rules.make_foe(rng)
	gifts = {}
	for c in Board.gen_gifts(size, gift_count, rng, links, foe_cells):
		gifts[c] = Rules.make_gift(rng)
	boss = Rules.make_foe(rng, true) if boss_fight else {}
	fight = {}
	dead = false
	notice = ""
	Audio.set_music("calm")
	tray.clear_foe()
	turns = 0
	roll = 0
	moves = []
	won = false
	busy = false
	if not keep:
		floors = 0
		kit = Rules.start_kit(size)
	if not (keep and carry_tokens):
		rerolls = 0
	die_index = mini(die_index, kit.size() - 1)
	rig.pan = Vector2.ZERO
	# Before anything is placed. Every cell is handed to the projection as coordinates, and coordinates for this board read against the last one are out of bounds on the axis this board just grew.
	view3d.size = size
	_reset_roamer()
	player.position = view3d.world(coords)
	ghosts.clear()
	_redraw()
	rig.fit()
	_refresh_tray()
	_refresh_hud()


## Beating the boss is not the end of anything but the floor. The run climbs a dimension, keeps the kit it fought for, and deals again.
## Nothing in this game cuts, and a whole board appearing where another one was is the biggest cut there could be. The floor you cleared falls away from the camera, then the next one arrives exploded into its planes and collapses into a deck -- which is the new dimension assembling itself, drawn by the one float that already describes the two layouts.
func _ascend() -> void:
	floors += 1
	Audio.play("win")
	view3d.win_burst()
	_go_to(Rules.floor_size(size.size() + 1), true)


## Swapping one board for another, without the swap being a cut. The board you are leaving falls away from the camera, the next one is dealt behind the dark, and then it assembles itself out of its own planes.
##
## Every path that changes `size` comes through here -- climbing a floor, and cycling the board with D -- because there is no version of a whole lattice appearing where another one was that does not read as a glitch.
func _go_to(to: PackedInt32Array, keep: bool) -> void:
	busy = true
	if anim:
		var from_zoom: float = rig.zoom
		var out := create_tween()
		out.tween_method(func(u: float): rig.set_zoom(lerpf(from_zoom, from_zoom * 3.5, u)),
				0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await out.finished
	size = to
	new_game(keep)
	# new_game() clears `busy` -- it is dealing a floor that is ready to play. This one is not ready yet: it is still coming together, and a roll landing in the middle of that would be a move made on a board the player cannot read.
	busy = true
	if anim:
		await _assemble()
	busy = false
	_refresh_hud()


## The new floor puts itself together. It starts at the far end of the spread from wherever the view sits, so it always travels: into a deck in FOCUS, out into a row in SPREAD.
func _assemble() -> void:
	var to := 1.0 if view == View.SPREAD else 0.0
	var from := 1.0 - to
	set_spread(from)
	var t := create_tween()
	t.tween_method(func(u: float): set_spread(lerpf(from, to, u)), 0.0, 1.0, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished


## Board and markers follow the game state; called whenever either changes.
func _redraw() -> void:
	# The chaser first: sync() draws, and drawing reads whatever chaser cell it was last handed.
	view3d.set_roamer(roamer, _roamer_next())
	view3d.sync(coords, links, moves, foes, gifts)


func _refresh_hud() -> void:
	# The tray is drawn from the kit every single time anything is redrawn, rather than by each place that changes the kit remembering to say so. One of them did not -- a lost boss round took a die and put the rematch straight up without touching the tray, so the screen showed a die that was already gone. The visual is a function of the data or it is a second copy of it that drifts.
	_refresh_tray()
	hud.refresh({
		"coords": coords, "size": size, "links": links, "moves": moves,
		"roll": roll, "turns": turns, "won": won,
		"kit": kit, "die_index": die_index,
		"rerolls": rerolls, "foes": foes, "gifts": gifts, "dead": dead,
		# The fight, with the contest list worked out here rather than worked out again by whatever is drawing it.
		"fight": fight if fight.is_empty() else _fight_view(),
		"roamer": roamer, "floors": floors, "notice": notice,
		"mode": "SPREAD" if view == View.SPREAD else "FOCUS",
	})


## The fight as the screen needs it: the state plus the contests actually on offer this round. Anything drawing it reads this, so nothing has to re-derive a rule and get a different answer.
func _fight_view() -> Dictionary:
	var view := fight.duplicate()
	view["left"] = games_left()
	return view


## The tray is the kit and the rerolls, as objects. Everything the HUD used to spell
## out in words is one of these.
func _refresh_tray() -> void:
	tray.set_kit(kit, die_index)
	tray.set_spares(rerolls)


## The die currently selected, as its list of face values.
func die() -> PackedInt32Array:
	return kit[die_index]


## One roll of a die. Every face is equally likely and a die may carry the same value twice, so this indexes the list rather than taking a range.
func throw(faces: PackedInt32Array) -> int:
	return faces[rng.randi_range(0, faces.size() - 1)]


## How far the chaser has to walk to reach you, in cells. On screen in the status line, because in a projected 4D view this cannot be counted by eye.
func roamer_dist() -> int:
	if roamer.is_empty():
		return -1
	return Board.manhattan(coords, roamer)


## Where the chaser steps next: the axis it is furthest from you on, ties to the lowest axis. Deterministic on purpose -- it is a clock, and a clock you can read is pressure while one you cannot is an ambush.
func _roamer_next() -> PackedInt32Array:
	if roamer.is_empty() or roamer == coords:
		return PackedInt32Array()
	var axis := -1
	var delta := 0
	for k in size.size():
		var d: int = coords[k] - roamer[k]
		if absi(d) > absi(delta):
			delta = d
			axis = k
	if axis < 0:
		return PackedInt32Array()
	var dest := roamer.duplicate()
	dest[axis] += signi(delta)
	return dest


## One step, after every roll -- a spent reroll moves it too, which is what stops the token from being free time.
func _step_roamer() -> void:
	if roamer.is_empty() or won or dead or not fight.is_empty():
		return
	var dest := _roamer_next()
	if dest.is_empty():
		return
	roamer = dest
	_place_roamer(true)
	if roamer == coords:
		# Caught. It picks the fight, which is the half of a fight you normally choose.
		_start_fight(roamer_foe, ROAMER_CELL)


## Puts it back at arm's length after a fight, carrying a different die than the one you just beat. It used to be made once per floor, so every catch was the same foe with the same faces -- win four of them and you were holding four copies of one die.
func _reset_roamer() -> void:
	# The chaser scales by its dice rather than its speed: a two-step chaser cannot be anticipated in a projected 4D view, and a clock you cannot read is an ambush rather than pressure.
	roamer_foe = Rules.make_foe(rng, false, size.size() >= 4)
	if not roamer_on:
		roamer = PackedInt32Array()
		roamer_node.visible = false
		return
	# Along the axis with the most room behind you, so it starts where you have already been rather than between you and the goal.
	var axis := 0
	for k in size.size():
		if coords[k] > coords[axis]:
			axis = k
	roamer = coords.duplicate()
	roamer[axis] = maxi(0, coords[axis] - HEAD_START)
	if roamer == coords:
		roamer[axis] = mini(size[axis] - 1, coords[axis] + HEAD_START)
	roamer_node.visible = true
	_place_roamer(false)


## Tweened like everything else. It is not awaited: the chaser moving while you are reading the board is the point, and blocking the turn on its hop would make every roll feel slower than it is.
func _place_roamer(animate: bool) -> void:
	if roamer.is_empty():
		return
	var to: Vector3 = view3d.world(roamer)
	if not anim or not animate:
		roamer_node.position = to
		return
	var t := create_tween()
	t.tween_property(roamer_node, "position", to, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Layout, camera and everything sitting on the board move together, so the deck
## visibly explodes instead of cutting between two arrangements.
func set_spread(s: float) -> void:
	view3d.spread = s
	player.position = view3d.world(coords)
	_place_roamer(false)
	view3d.redraw()
	rig.fit()
	ghosts.place()


## Tweens layout and camera together, so the deck visibly flattens out into a row
## rather than cutting between two pictures.
func _set_view(v: View) -> void:
	if view == v:
		return
	# Only FOCUS remembers where you left it. SPREAD is the flat reference view and
	# always returns to face-on: it is supposed to be the same picture every time, so
	# restoring a remembered angle there is more disorienting, not less.
	if view == View.FOCUS:
		parked[View.FOCUS] = Vector2(rig.yaw, rig.pitch)
	view = v
	view3d.flat = v == View.SPREAD
	var to_angle: Vector2 = parked.get(View.FOCUS, rig.A_ISO) if v == View.FOCUS else rig.A_FLAT
	rig.rebase(to_angle)
	var from_angle := Vector2(rig.yaw, rig.pitch)
	var from_spread: float = view3d.spread
	var to_spread := 1.0 if v == View.SPREAD else 0.0
	var t := create_tween()
	t.tween_method(func(u: float):
			var a := from_angle.lerp(to_angle, u)
			rig.yaw = a.x
			rig.pitch = a.y
			set_spread(lerpf(from_spread, to_spread, u)), 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_refresh_hud()


func _view_angle(v: View) -> Vector2:
	return rig.A_FLAT if v == View.SPREAD else rig.A_ISO


## Straight to a view with no tween. Used by the screenshot harness.
func snap_view(v: View) -> void:
	view = v
	view3d.flat = v == View.SPREAD
	var a := _view_angle(v)
	rig.yaw = a.x
	rig.pitch = a.y
	set_spread(1.0 if v == View.SPREAD else 0.0)
	_refresh_hud()


## Next board in SIZES, wrapping. Deals a fresh run, because changing the shape of the lattice invalidates every coordinate in the old one -- and it travels there, because a board changing shape is the biggest move the game can make and it is not allowed to cut either.
func _cycle_size() -> void:
	var i := Rules.SIZES.find(size)
	_go_to(Rules.SIZES[(i + 1) % Rules.SIZES.size()] if i >= 0 else Rules.SIZES[0], false)


func do_roll() -> void:
	_roll(true)


## Spends a token to roll again on the same turn. Nothing else undoes a bad roll, so
## this is the whole escape hatch -- and a reroll that traps you again earns another
## token, which is what stops a run of walls from spiralling.
func reroll() -> void:
	if busy or won or roll == 0 or rerolls <= 0:
		return
	rerolls -= 1
	_roll(false)
	# A reroll is the whole action: you spend the turn's time and stay where you are, so the chaser gets its step for it. That is what stops the token from being free time -- and unlike a roll, this is a step you chose to pay for.
	_step_roamer()


func _roll(spend_turn: bool) -> void:
	notice = ""
	roll = throw(die())
	if spend_turn:
		turns += 1
	moves = Board.legal_moves(coords, size, roll)
	Audio.play("roll")
	# The number comes up on the die that was thrown. It used to pop over the player,
	# which reads as something landing *on* them rather than a move they just made.
	tray.roll_to(roll)
	var trapped := Rules.grants_reroll(moves, coords, size)
	if trapped:
		rerolls += 1
		Audio.play("token")
	_refresh_tray()
	if trapped:
		tray.flash_spares()
	ghosts.show_moves(moves, links, foes, gifts)
	_redraw()
	_refresh_hud()


## Picks a die from the kit. Only between choices -- once markers are on the board the
## number keys are choosing one of them.
func _pick_die(i: int) -> void:
	if won or i >= kit.size():
		return
	die_index = i
	Audio.play("pick")
	_inspect(i)
	_refresh_tray()
	_refresh_hud()


## Picking a die says what it is: its faces, and nothing else.
##
## It used to print your chance at each contest, computed exactly. That was worse than the heuristic it replaced, not better -- a correct number beside every option is a solver, and reading the largest one and pressing SPACE is not a decision. Both dice are on screen and both are legible; working out that 1155 is poor against 1166 at BIGGER is the fight.
##
## Not the die's name either: "d3" and "faces 1 2 3" are the same sentence twice, and for an irregular die the name is the same digits again.
func _inspect(i: int) -> void:
	notice = "faces %s" % " ".join(Array(kit[i]).map(func(v): return str(v)))


## A click that did not drag. The tray is the only thing worth clicking: a die picks
## it up, a spare spends it. Board cells stay on the number keys, which is what keeps
## working when 5D offers ten directions.
func _click(pos: Vector2) -> void:
	if busy or won or dead:
		return
	var i: int = tray.die_at(pos)
	# Mid-fight the tray is the fight: a die is the one you stake, or the one you drop to make room for what you just won.
	if not fight.is_empty():
		if i >= 0:
			if fight["over"] == "":
				_pick_die(i)
		return
	if i >= 0:
		if moves.is_empty():
			_pick_die(i)
		return
	if tray.spare_at(pos):
		reroll()


func choose(i: int) -> void:
	if i < 0 or i >= moves.size():
		return
	var dest: PackedInt32Array = moves[i]["coords"]
	moves = []
	roll = 0
	ghosts.clear()
	busy = true
	# Which planes are lit changed the moment the move list emptied.
	_redraw()
	await _hop(dest, 0.35, Tween.TRANS_BOUNCE)
	view3d.land_flash(coords)

	var idx := Board.coords_to_index(coords, size)
	if links.has(idx):
		Audio.play("snake" if Rules.landing(coords, size, links) == "SNAKE" else "ladder")
		await _slide_link(Board.index_to_coords(links[idx], size))

	# Landing somewhere new changes which plane is lit and which frame is warm, and the roll has been spent -- the dice go back to showing their names rather than a number that has already been used.
	_redraw()
	_refresh_tray()
	busy = false

	# It moves after you do, not between your roll and your move. Stepping it on the roll meant a 4 that would have carried you clear could still be caught before you had touched a marker -- the roll is not the move, and being taken on a move you had not made yet is not a chase, it is a trap.
	_step_roamer()
	if not fight.is_empty():
		_refresh_hud()
		return

	var at := Board.coords_to_index(coords, size)
	# Picked up on the way past, no fight and no cost. A gift is not a prize -- it is the thing that keeps a kit that can no longer reach the goal from being the end of the run.
	if gifts.has(at):
		kit.append(gifts[at])
		notice = "picked up %s" % Rules.die_name(gifts[at])
		gifts.erase(at)
		Audio.play("token")
		view3d.result_flash(coords, true)
		_refresh_tray()
		_redraw()
	if coords == roamer:
		# You can walk into it as easily as it walks into you.
		_start_fight(roamer_foe, ROAMER_CELL)
	elif foes.has(at):
		_start_fight(foes[at], at)
	elif Board.dist_to_goal(coords, size) == 0:
		# The goal is where the boss stands. Reaching it is arriving at the fight, not winning -- otherwise the floor could be sprinted past for free.
		if boss.is_empty():
			_win()
		else:
			_start_fight(boss, -1)
	_refresh_hud()


func _win() -> void:
	won = true
	Audio.play("win")
	view3d.win_burst()


## A fight is one contest, decided on one roll each -- a beat inside the turn, not a mode you leave the board for. The boss takes two of three.
##
## **The die you stake is the die you commit.** Lose and the foe takes that one, so the question is never only which die wins the contest: it is also which die you can afford to lose. `cell` is the foe's cell, or -1 for the boss, which stands on the goal and is not in `foes`.
func _start_fight(foe: Dictionary, cell: int) -> void:
	# Three ways at once, because a fight that only changes a line of text is a fight nobody notices starting: a sting, the music, and a ring thrown at the cell it happens on.
	Audio.play("fight")
	Audio.set_music("fight")
	view3d.fight_flash(coords)
	notice = ""
	fight = {"foe": foe, "cell": cell, "game": -1, "pick": 0, "wins": 0, "losses": 0,
			"last": "", "over": ""}
	tray.set_foe(foe["faces"])
	_next_round()


## Who frames the contest and who chooses inside it -- the 分蛋糕 split. OPEN, the foe names the game and the choice left to you is which die to stake; TELL, its die is already on the table and the choice is which contest to hold it in.
func _next_round() -> void:
	var foe: Dictionary = fight["foe"]
	# A foe that names the contest leaves you the choice of which die to stake -- which is no choice at all while you are holding one. Down to a single die the foe shows its die instead and the naming comes to you, so every fight has a decision in it even at the bottom.
	var order: int = foe["trait"] if kit.size() > 1 else Rules.TELL
	fight["game"] = _foe_picks(foe) if order == Rules.OPEN else -1
	fight["pick"] = 0
	_refresh_hud()


## The foe reaches for whatever its own die is best at. One place decides that, so its choice and any hint the HUD grows cannot disagree.
func _foe_picks(foe: Dictionary) -> int:
	var best := -1
	var best_f := -1.0
	for g in games_left():
		var f: float = MG.ALL[g].favours(foe["faces"])
		if f > best_f:
			best_f = f
			best = g
	return best


## The contests this foe knows. All of them, every round.
##
## They used to be struck off as they were played, which was never a rule anybody asked for -- it was invented here, and then a boss carrying two contests ran out of them on its third round and the fight had nothing to offer and no way forward. A bag you take from and do not refill is a dead end waiting for the right foe.
func games_left() -> Array:
	return fight["foe"]["games"]


func _resolve() -> void:
	var foe: Dictionary = fight["foe"]
	if fight["game"] < 0:
		# TELL: the contest is whichever one is highlighted when SPACE lands.
		var left := games_left()
		fight["game"] = left[mini(fight["pick"], left.size() - 1)]
	var g: int = fight["game"]
	var mine := throw(die())
	var theirs := throw(foe["faces"])
	tray.roll_to(mine)
	tray.roll_foe(theirs)
	# A drawn round costs nothing and settles nothing: the contest stands, the dice go again. Losing a die because you matched the foe is not a result anybody reads as fair, and handing ties to the foe quietly made every die with repeated faces worse than it looks.
	if MG.ALL[g].draw(mine, theirs):
		fight["last"] = "%s  %d v %d  DRAW, again" % [MG.ALL[g].label(), mine, theirs]
		Audio.play("pick")
		_refresh_hud()
		return
	var win: bool = MG.ALL[g].play(mine, theirs)
	fight["last"] = "%s  %d v %d  %s" % [MG.ALL[g].label(), mine, theirs, "WON" if win else "LOST"]
	# Opposite sounds and opposite colours: which way a round went should not have to be read.
	Audio.play("gain" if win else "loss")
	view3d.result_flash(coords, win)
	if win:
		fight["wins"] += 1
	else:
		fight["losses"] += 1
	# A boss takes two of three; everything else is settled on the one roll.
	var need := 2 if foe["boss"] else 1
	if fight["wins"] >= need:
		# Settled, but not yet applied. The result stops here and waits to be read: a fight that resolves and cleans itself up in the same frame is a fight you only find out about by counting the dice on your tray afterwards.
		fight["over"] = "CLEARED" if foe["boss"] else "WON"
		Audio.play("ladder")
	elif fight["losses"] >= need:
		fight["over"] = "LOST"
		Audio.play("snake")
	else:
		_next_round()
	_refresh_hud()


## SPACE on a decided fight. Reading the result is a beat of its own, so this is where what it costs or pays actually happens.
func _settle() -> void:
	var over: String = fight["over"]
	fight["over"] = ""
	if over == "LOST":
		_fight_lost()
	elif over == "CLEARED":
		# The boss's die is the prize for the floor, and it was going nowhere: the win went straight to the climb and the fight ended having paid nothing at all.
		var prize: PackedInt32Array = fight["foe"]["faces"]
		kit.append(prize)
		notice = "BEAT THE BOSS  -  took %s" % Rules.die_name(prize)
		_end_fight()
		if boss_fight:
			_ascend()
		else:
			_win()
	else:
		_fight_won()


func _fight_won() -> void:
	var foe: Dictionary = fight["foe"]
	notice = "WON the fight  -  took %s" % Rules.die_name(foe["faces"])
	foes.erase(fight["cell"])
	# No cap: a won die is a gain, full stop. It used to be one die per axis, so a win over the cap forced a discard -- and a discard can leave you holding two of the same die and nothing else, which is how a run ends up unable to reach the goal at all.
	kit.append(foe["faces"])
	_end_fight()


func _fight_lost() -> void:
	var foe: Dictionary = fight["foe"]
	foes.erase(fight["cell"])
	_pay_for_loss()
	if dead:
		_end_fight()
		return
	# A lost boss is not a wall: you are still standing on the goal, so it comes straight back. Each attempt costs a die, which is how a weak kit bleeds out rather than getting locked out of the game with nothing left to do.
	if foe["boss"]:
		_start_fight(foe, -1)
		return
	_end_fight()


## What a lost fight costs. Holding more than one die, the foe takes the one you staked. Holding your last, it cannot be taken -- it breaks, losing its largest face, and only a die already worn to the minimum is lost outright.
##
## Without this the run is one coin flip long: you set out with one die, so the first foe you meet ends it half the time, and a game that can be over before the second roll is not a game.
func _pay_for_loss() -> void:
	if kit.size() > 1:
		notice = "LOST the fight  -  %s gone" % Rules.die_name(die())
		_lose_die(die_index)
		return
	var faces: PackedInt32Array = kit[0]
	if faces.size() <= Rules.MIN_FACES:
		notice = "LOST the fight  -  your last die shattered"
		kit.clear()
		dead = true
		Audio.set_music("over")
		return
	kit[0] = Rules.damaged(faces)
	notice = "LOST the fight  -  your last die cracks to %s" % Rules.die_name(kit[0])


func _lose_die(i: int) -> void:
	kit.remove_at(i)
	die_index = clampi(die_index, 0, maxi(0, kit.size() - 1))
	dead = kit.is_empty()


func _end_fight() -> void:
	Audio.set_music("calm")
	# Whatever the outcome, the chaser backs off. Left standing on you it would pick a fight on every roll from here to the goal, which is a stalemate rather than a clock.
	var was_roamer: bool = fight.get("cell", 0) == ROAMER_CELL
	fight = {}
	if was_roamer:
		_reset_roamer()
	tray.clear_foe()
	_refresh_tray()
	_refresh_hud()
	_redraw()


func _hop(dest: PackedInt32Array, secs: float, trans: Tween.TransitionType) -> void:
	if not anim:
		coords = dest
		player.position = view3d.world(dest)
		return
	Audio.play("hop")
	var t := create_tween()
	t.tween_property(player, "position", view3d.world(dest), secs) \
		.set_trans(trans).set_ease(Tween.EASE_OUT)
	await t.finished
	coords = dest


## A link fired the instant you landed, in a straight line, which reads as a cut
## rather than a move -- no beat to notice it happened, no sense of being dragged
## somewhere. Hold on the landing cell first, then bow the path out to one side so
## the travel is visibly a path and not a jump.
func _slide_link(dest: PackedInt32Array) -> void:
	if not anim:
		coords = dest
		player.position = view3d.world(dest)
		return
	var a := player.position
	var b: Vector3 = view3d.world(dest)
	var mid: Vector3 = a.lerp(b, 0.5) + rig.perp(b - a) * (b - a).length() * 0.18
	var t := create_tween()
	t.tween_interval(0.18)
	t.tween_method(func(u: float): player.position = _bezier(a, mid, b, u), 0.0, 1.0, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	coords = dest


func _bezier(a: Vector3, m: Vector3, b: Vector3, u: float) -> Vector3:
	return a.lerp(m, u).lerp(m.lerp(b, u), u)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				press_at = event.position
			elif event.position.distance_to(press_at) < 6.0:
				_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			rig.set_zoom(rig.zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			rig.set_zoom(rig.zoom * 1.1)
	elif event is InputEventMouseMotion and dragging:
		rig.orbit(event.relative)
	elif event is InputEventMouseMotion and panning:
		rig.pan_by(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		# ponytail: R, TAB and the number keys read raw keycodes rather than adding
		# input actions to project.godot. "roll" reuses the built-in ui_accept.
		# Shift, because a bare R sits next to every key you actually use and wipes the
		# game you were playing.
		if event.keycode == KEY_R and event.shift_pressed:
			# Back to the first floor, not the one you died on. A run restarting in 5D holding one die is not a run, and picking up where the last one ended is the one thing a restart must not do.
			_go_to(Rules.floor_size(2), false)
		elif event.keycode == KEY_ESCAPE:
			hud.toggle_help()
		elif event.keycode == KEY_QUESTION or event.keycode == KEY_SLASH:
			# Its own overlay rather than more of ESC's: one is the controls, the other is what the words on screen mean, and somebody looking for either does not want to read the other.
			hud.toggle_glossary()
		elif event.keycode == KEY_TAB:
			_set_view(View.FOCUS if view == View.SPREAD else View.SPREAD)
		elif event.keycode == KEY_C:
			# Orbit is free, which means it is easy to end up looking at nothing.
			# C flies the camera back to where the current view wants it, and forgets
			# the parked angle so the reset is not undone on the next trip through TAB.
			parked.erase(view)
			rig.fly_to(_view_angle(view))
		elif event.keycode == KEY_D and view3d.debug:
			# Debug only, behind F3. The floor is climbed now, not chosen -- but reaching a 5D fight by playing four floors first is no way to test one.
			_cycle_size()
		elif event.keycode == KEY_F3:
			view3d.debug = not view3d.debug
			_redraw()
			_refresh_hud()
		elif busy or won or dead:
			return
		elif event.is_action_pressed("ui_accept"):
			_commit()
		elif event.is_action_pressed("ui_left"):
			_cycle_die(-1)
		elif event.is_action_pressed("ui_right"):
			_cycle_die(1)
		elif event.is_action_pressed("ui_up"):
			_cycle_contest(-1)
		elif event.is_action_pressed("ui_down"):
			_cycle_contest(1)
		elif event.keycode == KEY_M:
			Audio.toggle_mute()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			# The number keys are the board's, and only the board's. Choosing a die, a contest or a die to drop is on the arrow keys, because a key that means two things means neither when you are being chased.
			choose(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			choose(9)


## SPACE, and it always means the same thing: commit to what is in front of you. No roll on the board, throw one; a roll you cannot live with, throw it again for a token; mid-fight, stake the die against the foe's; over the cap, drop the die you have highlighted.
##
## There is no separate reroll key. A reroll *is* another throw, so it is the same key -- X was a second word for one idea, and one nobody would have guessed.
func _commit() -> void:
	if not fight.is_empty():
		if fight["over"] != "":
			_settle()
		else:
			_resolve()
		return
	if roll == 0:
		do_roll()
	else:
		reroll()


## LEFT/RIGHT walk the kit: which die you are about to throw, which die you are staking, which die you are about to drop. Same key, one idea, in all three.
func _cycle_die(step: int) -> void:
	if kit.size() < 2:
		return
	# Blocked only on a result waiting to be read -- there is nothing left to choose there. It used to be blocked whenever the foe had not named a contest yet, which was wrong twice over: the die you have picked is the die you stake whoever names the contest, and it is also the only way to look at what your own dice are while a fight is on.
	if not fight.is_empty() and fight["over"] != "":
		return
	_pick_die(posmod(die_index + step, kit.size()))


## UP/DOWN walk the contests a foe has left, when the foe is the one who showed its die first and left the naming to you.
func _cycle_contest(step: int) -> void:
	if fight.is_empty() or fight["game"] >= 0 or fight["over"] != "":
		return
	var left := games_left()
	if left.size() < 2:
		return
	fight["pick"] = posmod(fight.get("pick", 0) + step, left.size())
	Audio.play("pick")
	_refresh_hud()
