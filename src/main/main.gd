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

@export var size := PackedInt32Array([6, 6, 6])
@export var link_count := 18
## Manhattan cap on a link's reach. Uncapped endpoints gave full-width lines that
## crossed everything and skipped most of the board in one move.
@export var link_span := 5
## Foes standing on the floor. Off (0) leaves a board with nothing to fight on the way, which is how test_play.gd keeps measuring that a random walk still reaches the goal.
@export var foe_count := 5
## The boss on the goal cell. Off means reaching the goal wins outright.
@export var boss_fight := true
## Off makes every hop instant, so test_play.gd can run games without waiting on tweens.
@export var anim := true

@onready var rig: Node3D = $CamRig
@onready var view3d: Node3D = $Board
@onready var ghosts: Node3D = $Ghosts
@onready var player: MeshInstance3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var tray: Node3D = $CamRig/Camera3D/Tray

var coords := PackedInt32Array()
var links := {}

## cell index -> foe. A foe leaves its cell once it has been fought, won or lost.
var foes := {}

## The foe standing on the goal. Best of three, and the only fight on the floor you cannot walk around.
var boss := {}

## The fight in progress, empty between them. A Dictionary rather than a class for the same reason a foe is one: the turn loop owns the state, and the fight is a state the turn is in rather than an object with a life of its own.
var fight := {}

## No dice left. The run is over -- there is nothing to roll and nothing to stake.
var dead := false

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


func new_game() -> void:
	coords = Board.index_to_coords(0, size)
	links = Board.gen_links(size, link_count, rng, link_span)
	foes = {}
	for c in Board.gen_foes(size, foe_count, rng, links):
		foes[c] = Rules.make_foe(rng)
	boss = Rules.make_foe(rng, true) if boss_fight else {}
	fight = {}
	dead = false
	tray.clear_foe()
	turns = 0
	roll = 0
	moves = []
	won = false
	busy = false
	rerolls = 0
	kit = Rules.kit(size)
	die_index = mini(die_index, kit.size() - 1)
	rig.pan = Vector2.ZERO
	view3d.size = size
	player.position = view3d.world(coords)
	ghosts.clear()
	_redraw()
	rig.fit()
	_refresh_tray()
	_refresh_hud()


## Board and markers follow the game state; called whenever either changes.
func _redraw() -> void:
	view3d.sync(coords, links, moves, foes)


func _refresh_hud() -> void:
	hud.refresh({
		"coords": coords, "size": size, "links": links, "moves": moves,
		"roll": roll, "turns": turns, "won": won,
		"kit": kit, "die_index": die_index,
		"rerolls": rerolls, "foes": foes, "fight": fight, "dead": dead,
		"mode": "SPREAD" if view == View.SPREAD else "FOCUS",
	})


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


## Layout, camera and everything sitting on the board move together, so the deck
## visibly explodes instead of cutting between two arrangements.
func set_spread(s: float) -> void:
	view3d.spread = s
	player.position = view3d.world(coords)
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


## Next board in SIZES, wrapping. Deals a fresh game, because changing the shape of
## the lattice invalidates every coordinate in the old one.
func _cycle_size() -> void:
	var i := Rules.SIZES.find(size)
	size = Rules.SIZES[(i + 1) % Rules.SIZES.size()] if i >= 0 else Rules.SIZES[0]
	new_game()


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


func _roll(spend_turn: bool) -> void:
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
	ghosts.show_moves(moves, links, foes)
	_redraw()
	_refresh_hud()


## Picks a die from the kit. Only between choices -- once markers are on the board the
## number keys are choosing one of them.
func _pick_die(i: int) -> void:
	if won or i >= kit.size():
		return
	die_index = i
	Audio.play("pick")
	_refresh_tray()
	_refresh_hud()


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
			if fight["discard"]:
				_discard(i)
			elif fight["game"] >= 0:
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

	# Landing somewhere new changes which plane is lit and which frame is warm.
	_redraw()
	busy = false
	var at := Board.coords_to_index(coords, size)
	if foes.has(at):
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
	Audio.play("snake")
	fight = {"foe": foe, "cell": cell, "game": -1, "wins": 0, "losses": 0,
			"used": [], "discard": false, "last": ""}
	tray.set_foe(foe["faces"])
	_next_round()


## Who frames the contest and who chooses inside it -- the 分蛋糕 split. OPEN, the foe names the game and the choice left to you is which die to stake; TELL, its die is already on the table and the choice is which contest to hold it in.
func _next_round() -> void:
	var foe: Dictionary = fight["foe"]
	fight["game"] = _foe_picks(foe) if foe["trait"] == Rules.OPEN else -1
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


## Contests this foe has not already used. A boss plays three different ones, so a round it has won is a round it cannot repeat.
func games_left() -> Array:
	var out := []
	for g in fight["foe"]["games"]:
		if not fight["used"].has(g):
			out.append(g)
	return out


## A number key inside a fight: which contest, if the foe left that open, otherwise which die to stake.
func _fight_key(i: int) -> void:
	if fight["discard"]:
		_discard(i)
		return
	if fight["game"] >= 0:
		_pick_die(i)
		return
	var left := games_left()
	if i < left.size():
		fight["game"] = left[i]
		_resolve()


func _resolve() -> void:
	var foe: Dictionary = fight["foe"]
	var g: int = fight["game"]
	fight["used"].append(g)
	var mine := throw(die())
	var theirs := throw(foe["faces"])
	tray.roll_to(mine)
	tray.roll_foe(theirs)
	var win: bool = MG.ALL[g].play(mine, theirs)
	fight["last"] = "%d v %d  %s" % [mine, theirs, "WON" if win else "LOST"]
	if win:
		fight["wins"] += 1
	else:
		fight["losses"] += 1
	# A boss takes two of three; everything else is settled on the one roll.
	var need := 2 if foe["boss"] else 1
	if fight["wins"] >= need:
		_fight_won()
	elif fight["losses"] >= need:
		_fight_lost()
	else:
		_next_round()
	_refresh_hud()


func _fight_won() -> void:
	var foe: Dictionary = fight["foe"]
	Audio.play("ladder")
	if foe["boss"]:
		_end_fight()
		_win()
		return
	foes.erase(fight["cell"])
	kit.append(foe["faces"])
	# Over the cap, taking a die means dropping one. That is the whole cost of winning: the kit's shape is bounded even when your luck is not.
	if kit.size() > Rules.kit_cap(size):
		fight["discard"] = true
		_refresh_tray()
		return
	_end_fight()


func _fight_lost() -> void:
	var foe: Dictionary = fight["foe"]
	Audio.play("snake")
	foes.erase(fight["cell"])
	_lose_die(die_index)
	if dead:
		_end_fight()
		return
	# A lost boss is not a wall: you are still standing on the goal, so it comes straight back. Each attempt costs a die, which is how a weak kit bleeds out rather than getting locked out of the game with nothing left to do.
	if foe["boss"]:
		_start_fight(foe, -1)
		return
	_end_fight()


func _lose_die(i: int) -> void:
	kit.remove_at(i)
	die_index = clampi(die_index, 0, maxi(0, kit.size() - 1))
	dead = kit.is_empty()


func _discard(i: int) -> void:
	if i >= kit.size():
		return
	kit.remove_at(i)
	die_index = clampi(die_index, 0, kit.size() - 1)
	Audio.play("pick")
	_end_fight()


func _end_fight() -> void:
	fight = {}
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
			new_game()
		elif event.keycode == KEY_ESCAPE:
			hud.toggle_help()
		elif event.keycode == KEY_TAB:
			_set_view(View.FOCUS if view == View.SPREAD else View.SPREAD)
		elif event.keycode == KEY_C:
			# Orbit is free, which means it is easy to end up looking at nothing.
			# C flies the camera back to where the current view wants it, and forgets
			# the parked angle so the reset is not undone on the next trip through TAB.
			parked.erase(view)
			rig.fly_to(_view_angle(view))
		elif event.keycode == KEY_D:
			_cycle_size()
		elif event.keycode == KEY_F3:
			view3d.debug = not view3d.debug
			_redraw()
			_refresh_hud()
		elif busy or won or dead:
			return
		elif event.is_action_pressed("ui_accept"):
			# Same key, one meaning: throw. Mid-fight it throws the die you have picked against the foe's, once the contest is known.
			if not fight.is_empty():
				if fight["game"] >= 0 and not fight["discard"]:
					_resolve()
			elif moves.is_empty():
				do_roll()
		elif event.keycode == KEY_M:
			Audio.toggle_mute()
		elif event.keycode == KEY_X:
			reroll()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			# Same keys, disjoint states: a fight means they are choosing a contest, a die to stake or a die to drop; markers on the board mean they are choosing a move; neither means they are choosing the next die.
			if not fight.is_empty():
				_fight_key(event.keycode - KEY_1)
			elif moves.is_empty():
				_pick_die(event.keycode - KEY_1)
			else:
				choose(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			choose(9)
