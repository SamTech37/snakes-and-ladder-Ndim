extends Node3D

## N-dimensional Snakes & Ladders. Roll gives distance, you pick the axis.
## Nodes, materials and the environment live in main.tscn beside this file; the
## script only does what cannot be authored by hand — the lattice mesh (its
## geometry depends on `size`), the turn loop, and input.

const Board = preload("res://src/board/board.gd")
const AXIS_NAMES := "XYZWVU"

## Flat color, nothing over 1.0. The environment does no glow and no filmic tonemap,
## so what is written here is what lands on screen; separation comes from brightness
## against black, the way it does in every one of the reference plates. The lattice
## is a dim violet -> teal gradient that reads as one receding surface, and anything
## playable sits near full brightness on top of it.
const C_SHELL_START := Color(0.26, 0.10, 0.38)
const C_SHELL_GOAL := Color(0.09, 0.34, 0.40)
## Warm, so the player's own rays never read as another lattice line.
const C_CROSS := Color(0.78, 0.46, 0.13)
const C_LADDER := Color(0.49, 1.0, 0.31)
const C_SNAKE := Color(1.0, 0.24, 0.60)
const C_GOAL := Color(1.0, 0.89, 0.25)

## A cube's silhouette is smaller than its circumsphere -- between 0.58 (seen down a
## face normal) and 0.82 (down the body diagonal) of it. Fitting the sphere itself
## left the board at a third of the frame; 0.8 clipped the near corner off the bottom.
const FIT := 0.9

@export var size := PackedInt32Array([10, 10, 10])
@export var link_count := 40
## Manhattan cap on a link's reach. Uncapped endpoints gave full-width lines that
## crossed everything and skipped most of the board in one move.
@export var link_span := 5
## Off makes every hop instant, so test_play.gd can run games without waiting on tweens.
@export var anim := true
@export var ghost_scene: PackedScene

@onready var rig: Node3D = $CamRig
@onready var cam: Camera3D = $CamRig/Camera3D
@onready var grid: MeshInstance3D = $Grid
@onready var ghosts: Node3D = $Ghosts
@onready var player: MeshInstance3D = $Player
@onready var crosshair: MeshInstance3D = $Player/Crosshair
@onready var status: Label = $HUD/Margin/Rows/Status
@onready var menu: Label = $HUD/Margin/Rows/Moves

var coords := PackedInt32Array()
var links := {}
var roll := 0
var moves := []
var turns := 0
var busy := false
var won := false
var rng := RandomNumberGenerator.new()

## Deliberately off the (1,1,1) diagonal, or the start corner hides exactly
## behind the goal corner on the first frame.
var yaw := 0.25
var pitch := -0.35
var cam_dist := 20.0
var dragging := false
## Which extreme of each axis currently faces away from the camera. Orbiting past an
## axis plane swaps a wall, and only then does the mesh need rebuilding.
var face_keep := PackedInt32Array()


func _ready() -> void:
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
	player.position = Board.coords_to_world(coords, size)
	# Camera first: which walls get drawn depends on where it ends up.
	_frame_camera()
	rig.rotation = Vector3(pitch, yaw, 0.0)
	face_keep = _far_faces()
	_draw_board()
	_build_crosshair()
	_clear_ghosts()
	_refresh_hud()


## The extreme of each axis on the far side of the board from the camera.
func _far_faces() -> PackedInt32Array:
	var eye := cam.global_position - rig.position
	var keep := PackedInt32Array()
	keep.resize(size.size())
	for j in size.size():
		keep[j] = 0 if eye[j % 3] > 0.0 else size[j] - 1
	return keep


## Fills the Grid node's ImmediateMesh: the lattice shell plus every teleport.
## Colors come from vertex color; the material is on the node, set in the scene.
func _draw_board() -> void:
	var im: ImmediateMesh = grid.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var span := maxi(1, Board.dist_to_goal(Board.index_to_coords(0, size), size))
	for i in Board.total_cells(size):
		var c := Board.index_to_coords(i, size)
		for k in size.size():
			if c[k] + 1 >= size[k] or not Board.on_open_faces(c, size, k, face_keep):
				continue
			var d := c.duplicate()
			d[k] += 1
			_seg(im, Board.coords_to_world(c, size), _shell_color(c, span),
					Board.coords_to_world(d, size), _shell_color(d, span))

	for a in links:
		var ca := Board.index_to_coords(a, size)
		var cb := Board.index_to_coords(links[a], size)
		var up := Board.dist_to_goal(cb, size) < Board.dist_to_goal(ca, size)
		_arrow(im, Board.coords_to_world(ca, size), Board.coords_to_world(cb, size),
				C_LADDER if up else C_SNAKE)

	_cross(im, Board.coords_to_world(Board.goal_coords(size), size), 0.6, C_GOAL)
	im.surface_end()


## Violet at the start corner, cyan at the goal: the gradient doubles as the progress bar.
func _shell_color(c: PackedInt32Array, span: int) -> Color:
	return C_SHELL_START.lerp(C_SHELL_GOAL, 1.0 - float(Board.dist_to_goal(c, size)) / span)


func _seg(im: ImmediateMesh, a: Vector3, ca: Color, b: Vector3, cb: Color) -> void:
	im.surface_set_color(ca)
	im.surface_add_vertex(a)
	im.surface_set_color(cb)
	im.surface_add_vertex(b)


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	_seg(im, a, color, b, color)


## A link as a bare segment says nothing about which end it runs to -- from a random
## orbit angle a ladder and a snake are the same stick. The chevron points at the
## destination, so direction is readable without knowing the color code.
func _arrow(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	_line(im, a, b, color)
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized() * 0.28
	var tip := a.lerp(b, 0.72)
	var back := tip - dir * 0.45
	_line(im, tip, back + side, color)
	_line(im, tip, back - side, color)


func _cross(im: ImmediateMesh, at: Vector3, r: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_line(im, at - axis * r, at + axis * r, color)


## Three rays through the player, parented to it so they follow for free. A 0.3-unit
## sphere somewhere inside a ten-deep lattice is a dot in a haystack; the rays say
## which row, column and file you are standing in.
func _build_crosshair() -> void:
	var reach := 0.0
	for k in mini(3, size.size()):
		reach = maxf(reach, float(size[k] - 1))
	var im: ImmediateMesh = crosshair.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(im, -axis * reach, axis * reach, C_CROSS)
	im.surface_end()


func _frame_camera() -> void:
	var far := Board.coords_to_world(Board.goal_coords(size), size)
	rig.position = far * 0.5
	# Fit whichever FOV axis is tighter. Fitting the vertical alone clipped the board
	# off the sides of any window narrower than 16:9.
	var vfov := deg_to_rad(cam.fov)
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var hfov := 2.0 * atan(tan(vfov * 0.5) * aspect)
	cam_dist = (far.length() * 0.5 * FIT + 0.8) / sin(minf(vfov, hfov) * 0.5)
	cam.position = Vector3(0.0, 0.0, cam_dist)


func _clear_ghosts() -> void:
	# free(), not queue_free(): deferred frees only collect at end of frame, so a
	# caller that takes many turns without yielding piles up every marker ever made.
	for g in ghosts.get_children():
		ghosts.remove_child(g)
		g.free()


## One numbered marker per legal move. Numbers, not mouse picking, because
## numbers keep working when 5D offers ten directions.
func _show_ghosts() -> void:
	_clear_ghosts()
	for i in moves.size():
		var g := ghost_scene.instantiate()
		g.position = Board.coords_to_world(moves[i]["coords"], size)
		g.get_node("Number").text = str(i + 1)
		ghosts.add_child(g)


func _move_label(m: Dictionary) -> String:
	var sign_char := "+" if m["dir"] > 0 else "-"
	var axis: int = m["axis"]
	var axis_name := AXIS_NAMES[axis] if axis < AXIS_NAMES.length() else str(axis)
	return "%s%s -> (%s)" % [sign_char, axis_name, ", ".join(Array(m["coords"]).map(func(v): return str(v)))]


func _refresh_hud() -> void:
	if won:
		status.text = "WIN in %d turns  -  R to restart" % turns
		menu.text = ""
		return
	var here := "(%s)" % ", ".join(Array(coords).map(func(v): return str(v)))
	if roll == 0:
		status.text = "at %s  -  turn %d  -  SPACE to roll d%d" % [here, turns, die_faces()]
		menu.text = "%dD board %s  -  drag to orbit, wheel to zoom, R to restart" % [size.size(), str(size)]
		return
	status.text = "rolled %d  -  at %s  -  turn %d" % [roll, here, turns]
	if moves.is_empty():
		menu.text = "no legal move, turn forfeit  -  SPACE to roll again"
		return
	var lines := PackedStringArray()
	for i in moves.size():
		lines.append("%d)  %s" % [i + 1, _move_label(moves[i])])
	menu.text = "\n".join(lines)


## d6, except on a board too narrow for it: an axis of extent 5 can only ever be
## crossed in steps of 1..4, so a 5 or a 6 there would be a guaranteed forfeit.
func die_faces() -> int:
	var f := 1
	for s in size:
		f = maxi(f, s - 1)
	return mini(f, 6)


func do_roll() -> void:
	roll = rng.randi_range(1, die_faces())
	turns += 1
	moves = Board.legal_moves(coords, size, roll)
	_show_ghosts()
	_refresh_hud()
	if moves.is_empty():
		roll = 0


func choose(i: int) -> void:
	if i < 0 or i >= moves.size():
		return
	var dest: PackedInt32Array = moves[i]["coords"]
	moves = []
	roll = 0
	_clear_ghosts()
	busy = true
	await _hop(dest, 0.35, Tween.TRANS_BOUNCE)

	var idx := Board.coords_to_index(coords, size)
	if links.has(idx):
		await _slide_link(Board.index_to_coords(links[idx], size))

	won = Board.dist_to_goal(coords, size) == 0
	busy = false
	_refresh_hud()


func _hop(dest: PackedInt32Array, secs: float, trans: Tween.TransitionType) -> void:
	if not anim:
		coords = dest
		player.position = Board.coords_to_world(dest, size)
		return
	var t := create_tween()
	t.tween_property(player, "position", Board.coords_to_world(dest, size), secs) \
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
		player.position = Board.coords_to_world(dest, size)
		return
	var a := player.position
	var b := Board.coords_to_world(dest, size)
	var side := (b - a).cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = (b - a).cross(Vector3.RIGHT)
	var mid := a.lerp(b, 0.5) + side.normalized() * (b - a).length() * 0.18
	var t := create_tween()
	t.tween_interval(0.18)
	t.tween_method(func(u: float): player.position = _bezier(a, mid, b, u), 0.0, 1.0, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	coords = dest


func _bezier(a: Vector3, m: Vector3, b: Vector3, u: float) -> Vector3:
	return a.lerp(m, u).lerp(m.lerp(b, u), u)


func _process(delta: float) -> void:
	if not dragging:
		yaw += delta * 0.12
	rig.rotation = Vector3(pitch, yaw, 0.0)
	var keep := _far_faces()
	if keep != face_keep:
		face_keep = keep
		_draw_board()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = maxf(3.0, cam_dist - 1.5)
			cam.position = Vector3(0.0, 0.0, cam_dist)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist += 1.5
			cam.position = Vector3(0.0, 0.0, cam_dist)
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.006, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		# ponytail: R and the number keys read raw keycodes rather than adding
		# input actions to project.godot. "roll" reuses the built-in ui_accept.
		if event.keycode == KEY_R:
			new_game()
		elif busy or won:
			return
		elif event.is_action_pressed("ui_accept") and moves.is_empty():
			do_roll()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			choose(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			choose(9)
