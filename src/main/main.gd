extends Node3D

## N-dimensional Snakes & Ladders. Roll gives distance, you pick the axis.
## Nodes, materials and the environment live in main.tscn beside this file; the
## script only does what cannot be authored by hand — the lattice mesh (its
## geometry depends on `size`), the turn loop, and input.

const Board = preload("res://src/board/board.gd")
const AXIS_NAMES := "XYZWVU"
const C_GRID := Color(0.05, 0.11, 0.26)
const C_LADDER := Color(0.2, 1.6, 1.4)
const C_SNAKE := Color(1.6, 0.2, 0.9)
const C_GOAL := Color(1.4, 1.3, 0.3)

@export var size := PackedInt32Array([10, 10, 10])
@export var link_count := 40
## Off makes every hop instant, so test_play.gd can run games without waiting on tweens.
@export var anim := true
@export var ghost_scene: PackedScene

@onready var rig: Node3D = $CamRig
@onready var cam: Camera3D = $CamRig/Camera3D
@onready var grid: MeshInstance3D = $Grid
@onready var ghosts: Node3D = $Ghosts
@onready var player: MeshInstance3D = $Player
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


func _ready() -> void:
	rng.randomize()
	new_game()


func new_game() -> void:
	coords = Board.index_to_coords(0, size)
	links = Board.gen_links(size, link_count, rng)
	turns = 0
	roll = 0
	moves = []
	won = false
	busy = false
	player.position = Board.coords_to_world(coords, size)
	_draw_board()
	_frame_camera()
	_clear_ghosts()
	_refresh_hud()


## Fills the Grid node's ImmediateMesh: lattice edges plus every teleport.
## Colors come from vertex color; the material is on the node, set in the scene.
func _draw_board() -> void:
	var im: ImmediateMesh = grid.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var n := Board.total_cells(size)
	for i in n:
		var c := Board.index_to_coords(i, size)
		for k in size.size():
			if c[k] + 1 >= size[k]:
				continue
			var d := c.duplicate()
			d[k] += 1
			_line(im, Board.coords_to_world(c, size), Board.coords_to_world(d, size), C_GRID)

	for a in links:
		var ca := Board.index_to_coords(a, size)
		var cb := Board.index_to_coords(links[a], size)
		var up := Board.dist_to_goal(cb, size) < Board.dist_to_goal(ca, size)
		_line(im, Board.coords_to_world(ca, size), Board.coords_to_world(cb, size), C_LADDER if up else C_SNAKE)

	_cross(im, Board.coords_to_world(Board.goal_coords(size), size), 0.45, C_GOAL)
	im.surface_end()


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	im.surface_set_color(color)
	im.surface_add_vertex(a)
	im.surface_set_color(color)
	im.surface_add_vertex(b)


func _cross(im: ImmediateMesh, at: Vector3, r: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_line(im, at - axis * r, at + axis * r, color)


func _frame_camera() -> void:
	var far := Board.coords_to_world(Board.goal_coords(size), size)
	rig.position = far * 0.5
	cam_dist = maxf(far.x, maxf(far.y, far.z)) * 1.4 + 3.0
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
		await _hop(Board.index_to_coords(links[idx], size), 0.5, Tween.TRANS_SINE)

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


func _process(delta: float) -> void:
	if not dragging:
		yaw += delta * 0.12
	rig.rotation = Vector3(pitch, yaw, 0.0)


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
