extends Node3D

## N-dimensional Snakes & Ladders. Roll gives distance, you pick the axis.
##
## This is the turn loop and the input map, and nothing else. The board's geometry is
## `Board/board_view.gd`, the camera is `CamRig/cam_rig.gd`, the markers are
## `Ghosts/ghosts.gd`, the text is `HUD/hud.gd`, and the rules that can be measured
## without a scene are `src/game/rules.gd`. Nodes and materials live in main.tscn.

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")

enum View { SPREAD, FOCUS }

@export var size := PackedInt32Array([6, 6, 6])
@export var link_count := 18
## Manhattan cap on a link's reach. Uncapped endpoints gave full-width lines that
## crossed everything and skipped most of the board in one move.
@export var link_span := 5
## Off makes every hop instant, so test_play.gd can run games without waiting on tweens.
@export var anim := true

@onready var rig: Node3D = $CamRig
@onready var view3d: Node3D = $Board
@onready var ghosts: Node3D = $Ghosts
@onready var player: MeshInstance3D = $Player
@onready var hud: CanvasLayer = $HUD

var coords := PackedInt32Array()
var links := {}
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

## Which die in `Rules.kit(size)` the next roll uses. A big die is dead weight against
## a wall -- picking the small one is how the endgame is played rather than endured.
var die_index := 0

## Spent with X to roll again without spending a turn. Earned on any roll that traps
## you, so the compensation arrives exactly when the wall does.
var rerolls := 0

var dragging := false
var panning := false


func _ready() -> void:
	# Everything each part needs from another is wired here, once, rather than left to
	# scripts reaching up through the tree for their neighbours.
	view3d.rig = rig
	rig.board = view3d
	rig.hud = hud
	ghosts.board = view3d
	view3d.fx = anim

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
	turns = 0
	roll = 0
	moves = []
	won = false
	busy = false
	rerolls = 0
	die_index = mini(die_index, Rules.kit(size).size() - 1)
	rig.pan = Vector2.ZERO
	view3d.size = size
	player.position = view3d.world(coords)
	ghosts.clear()
	_redraw()
	rig.fit()
	_refresh_hud()


## Board and markers follow the game state; called whenever either changes.
func _redraw() -> void:
	view3d.sync(coords, links, moves)


func _refresh_hud() -> void:
	hud.refresh({
		"coords": coords, "size": size, "links": links, "moves": moves,
		"roll": roll, "turns": turns, "won": won,
		"faces": die_faces(), "kit": Rules.kit(size), "die_index": die_index,
		"rerolls": rerolls,
		"mode": "SPREAD" if view == View.SPREAD else "FOCUS",
	})


## Faces on the die currently selected.
func die_faces() -> int:
	return Rules.kit(size)[die_index]


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
	roll = rng.randi_range(1, die_faces())
	if spend_turn:
		turns += 1
	moves = Board.legal_moves(coords, size, roll)
	Audio.play("roll")
	view3d.roll_pop(roll, coords)
	if Rules.grants_reroll(moves, coords, size):
		rerolls += 1
		Audio.play("token")
	ghosts.show_moves(moves, links)
	_redraw()
	_refresh_hud()


## Picks a die from the kit. Only between choices -- once markers are on the board the
## number keys are choosing one of them.
func _pick_die(i: int) -> void:
	if won or i >= Rules.kit(size).size():
		return
	die_index = i
	_refresh_hud()


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
	won = Board.dist_to_goal(coords, size) == 0
	if won:
		Audio.play("win")
		view3d.win_burst()
	busy = false
	_refresh_hud()


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
		if event.keycode == KEY_R:
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
		elif busy or won:
			return
		elif event.is_action_pressed("ui_accept") and moves.is_empty():
			do_roll()
		elif event.keycode == KEY_M:
			Audio.toggle_mute()
		elif event.keycode == KEY_X:
			reroll()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			# Same keys, two disjoint states: markers on the board means they are
			# choosing a move, no markers means they are choosing the next die.
			if moves.is_empty():
				_pick_die(event.keycode - KEY_1)
			else:
				choose(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			choose(9)
