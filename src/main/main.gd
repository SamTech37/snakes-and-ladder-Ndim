extends Node3D

## N-dimensional Snakes & Ladders. Roll gives distance, you pick the axis.
## Nodes, materials and the environment live in main.tscn beside this file; the
## script only does what cannot be authored by hand — the board mesh (its geometry
## depends on `size`), the turn loop, and input.

const Board = preload("res://src/board/board.gd")
const AXIS_NAMES := "XYZWVU"

## Flat color, nothing over 1.0. The environment does no glow and no filmic tonemap,
## so what is written here is what lands on screen; separation comes from brightness
## against black, the way it does in every one of the reference plates. The board is
## a dim violet -> teal gradient that reads as one receding surface, and anything
## playable sits near full brightness on top of it.
const C_SHELL_START := Color(0.26, 0.10, 0.38)
const C_SHELL_GOAL := Color(0.09, 0.34, 0.40)
const C_FRAME := Color(0.17, 0.17, 0.26)
## Warm, so the plane you are standing on never reads as another board line.
const C_HERE := Color(0.78, 0.46, 0.13)
const C_LADDER := Color(0.49, 1.0, 0.31)
const C_SNAKE := Color(1.0, 0.24, 0.60)
const C_GOAL := Color(1.0, 0.89, 0.25)

## What a plane that is neither yours nor a destination drops to. Dimmed, not hidden:
## the stack has to stay visible or FOCUS stops being a view of the board.
const DIM := 0.22

## Length of the cone at the destination end of a link.
const HEAD_LEN := 0.7

enum View { SPREAD, FOCUS }

## Each view has a camera angle as well as a layout, and the angle is half of what
## makes them different views rather than one view at two spacings. FOCUS looks at
## the deck from an isometric corner so the planes read as stacked cards; SPREAD
## looks at the board dead-on so the planes come out as flat squares in a row.
## Orbit is untouched afterwards -- switching view just parks the camera somewhere
## sensible for that view.
## FOCUS looks at the cube nearly square-on with just enough turn to see that the
## slices are separated in depth. 45 degrees of yaw and 35 of pitch -- a true
## isometric corner -- was in here for no reason I ever justified, and it renders
## every plane as a leaning parallelogram: seen from a corner, a cube has no square
## face pointing at you.
const A_ISO := Vector2(0.30, -0.16)
const A_FLAT := Vector2(0.0, 0.0)

## Boards D cycles through, so the higher-dimensional ones are reachable from inside
## the game rather than only by editing the export or a test script.
## ponytail: static var, not const -- PackedInt32Array literals are not constant
## expressions, so a const array of them will not parse.
## ponytail: 5D is deliberately not in here. The code generalises to it and it drew
## fine, but 3D and 4D are not right yet and shipping a third broken view only makes
## it harder to tell which one is wrong. Add [3,3,3,3,3] back when 3D and 4D are good.
static var SIZES: Array[PackedInt32Array] = [
	PackedInt32Array([6, 6, 6]),
	PackedInt32Array([4, 4, 4, 4]),
]

@export var size := PackedInt32Array([6, 6, 6])
@export var link_count := 18
## Manhattan cap on a link's reach. Uncapped endpoints gave full-width lines that
## crossed everything and skipped most of the board in one move.
@export var link_span := 5
## Off makes every hop instant, so test_play.gd can run games without waiting on tweens.
@export var anim := true
@export var ghost_scene: PackedScene

@onready var rig: Node3D = $CamRig
@onready var cam: Camera3D = $CamRig/Camera3D
@onready var grid: MeshInstance3D = $Grid
@onready var shafts: MultiMeshInstance3D = $Shafts
@onready var heads: MultiMeshInstance3D = $Heads
@onready var dots: MultiMeshInstance3D = $Dots
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
var view := View.FOCUS
var rng := RandomNumberGenerator.new()

## 0 = planes stacked like a deck, 1 = pulled apart into one row. Tweened by TAB, so
## the stack visibly explodes instead of cutting between two layouts.
var spread := 0.0

## Orbit stays free: every fixed view is a subset of it, and without it there is no
## way to judge which angles are worth fixing on.
var yaw := A_ISO.x
var pitch := A_ISO.y

## Where the camera was left in FOCUS, so TAB-ing back returns to the angle you were
## using rather than snapping to the default. SPREAD is deliberately not remembered.
var parked := {}
var zoom := 20.0
## Half the board's depth along the view axis, so the camera can be pulled back clear
## of the nearest plane rather than starting inside the stack.
var half_depth := 0.0
var dragging := false


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
	player.position = _world(coords)
	_draw_board()
	_frame_camera()
	_clear_ghosts()
	_refresh_hud()


func _world(c: PackedInt32Array) -> Vector3:
	return Board.coords_to_world(c, size, spread)


## Planes the player can see into: the one being stood on, plus wherever this turn's
## legal moves land. Everything else draws at DIM.
func _lit_planes() -> Dictionary:
	var lit := {Board.plane_of(coords, size): true}
	for m in moves:
		lit[Board.plane_of(m["coords"], size)] = true
	return lit


## Fills the Grid node's ImmediateMesh: one grid per plane, every plane's frame, and
## every link. Colors come from vertex color; the material is on the node, set in
## the scene. In FOCUS the planes you are not on are dimmed rather than dropped --
## the stack has to stay there or it stops being a view of the board.
func _draw_board() -> void:
	var im: ImmediateMesh = grid.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var span := maxi(1, Board.dist_to_goal(Board.index_to_coords(0, size), size))
	var here := Board.plane_of(coords, size)
	var lit := _lit_planes()

	for i in Board.total_cells(size):
		var c := Board.index_to_coords(i, size)
		var f := _fade(Board.plane_of(c, size), lit)
		# Only axes 0 and 1 run inside a plane; a step along any higher axis leaves
		# for another plane and is not drawn as an edge.
		for k in mini(2, size.size()):
			if c[k] + 1 >= size[k]:
				continue
			var d := c.duplicate()
			d[k] += 1
			_seg(im, _world(c), _shell_color(c, span) * f, _world(d), _shell_color(d, span) * f)

	for p in Board.plane_count(size):
		_plane_frame(im, p, (C_HERE if p == here else C_FRAME) * _fade(p, lit))

	_star(im, _world(Board.goal_coords(size)), 0.45, C_GOAL)
	im.surface_end()
	_draw_links(lit)


## Links are real geometry, not lines and not billboards: a shaft cylinder, a cone
## landing on the destination cell, and a sphere at each end, instanced through
## MultiMesh. Camera-facing quads were tried first and read as flat paper because
## that is exactly what they were -- these pierce the stack and foreshorten properly
## because the renderer is doing it rather than the script.
func _draw_links(lit: Dictionary) -> void:
	var n := links.size()
	for mm in [shafts.multimesh, heads.multimesh, dots.multimesh]:
		mm.instance_count = 0
	shafts.multimesh.instance_count = n
	heads.multimesh.instance_count = n
	dots.multimesh.instance_count = n * 2

	var i := 0
	for a in links:
		var ca := Board.index_to_coords(a, size)
		var cb := Board.index_to_coords(links[a], size)
		var up := Board.dist_to_goal(cb, size) < Board.dist_to_goal(ca, size)
		var f := maxf(_fade(Board.plane_of(ca, size), lit), _fade(Board.plane_of(cb, size), lit))
		var color := (C_LADDER if up else C_SNAKE) * f
		var wa := _world(ca)
		var wb := _world(cb)
		var head := minf(HEAD_LEN, wa.distance_to(wb) * 0.5)
		var neck := wb - (wb - wa).normalized() * head

		shafts.multimesh.set_instance_transform(i, _span(wa, neck))
		shafts.multimesh.set_instance_color(i, color)
		heads.multimesh.set_instance_transform(i, _span(neck, wb))
		heads.multimesh.set_instance_color(i, color)
		for e in 2:
			dots.multimesh.set_instance_transform(i * 2 + e, Transform3D(Basis(), wb if e else wa))
			dots.multimesh.set_instance_color(i * 2 + e, color)
		i += 1


## Places a unit-height mesh that runs along its own +Y so it spans `from` to `to`.
func _span(from: Vector3, to: Vector3) -> Transform3D:
	var d := to - from
	var len := d.length()
	if len < 0.0001:
		return Transform3D(Basis().scaled(Vector3.ZERO), from)
	var y := d / len
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Transform3D(Basis(x, y * len, x.cross(y)), (from + to) * 0.5)


## Full brightness on a lit plane, DIM elsewhere. SPREAD lights everything: once the
## planes are pulled apart nothing is hidden behind anything, so nothing needs dimming.
func _fade(p: int, lit: Dictionary) -> float:
	if view == View.SPREAD or lit.has(p):
		return 1.0
	return DIM


## Violet at the start corner, teal at the goal: the gradient doubles as the progress bar.
func _shell_color(c: PackedInt32Array, span: int) -> Color:
	return C_SHELL_START.lerp(C_SHELL_GOAL, 1.0 - float(Board.dist_to_goal(c, size)) / span)


## Outline around one plane, drawn through the projection so it tilts and slides with
## the plane it belongs to. The player's own is warm -- that is what says which plane
## you are standing on when the stack is packed.
func _plane_frame(im: ImmediateMesh, p: int, color: Color) -> void:
	var w := (size[0] - 1) if size.size() > 0 else 0
	var h := (size[1] - 1) if size.size() > 1 else 0
	# The first cell of plane p, since index = c0 + c1*size0 + p*size0*size1.
	var seed_cell := Board.index_to_coords(p * size[0] * (size[1] if size.size() > 1 else 1), size)
	var corners: Array[Vector3] = []
	for xy in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(w, h), Vector2i(0, h)]:
		var c := seed_cell.duplicate()
		c[0] = xy.x
		if c.size() > 1:
			c[1] = xy.y
		corners.append(_world(c))
	# Push each corner out along the plane's own diagonal so the frame clears the grid.
	var mid := (corners[0] + corners[2]) * 0.5
	for i in 4:
		corners[i] += (corners[i] - mid).normalized() * 0.8
	for i in 4:
		_line(im, corners[i], corners[(i + 1) % 4], color)


func _seg(im: ImmediateMesh, a: Vector3, ca: Color, b: Vector3, cb: Color) -> void:
	im.surface_set_color(ca)
	im.surface_add_vertex(a)
	im.surface_set_color(cb)
	im.surface_add_vertex(b)


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	_seg(im, a, color, b, color)


## Perpendicular to `v` across the screen. Taken against the camera's forward vector
## rather than a fixed axis: the planes are tilted in 3D now, so a chevron built in
## the xy plane would collapse to nothing at most orbit angles.
func _perp(v: Vector3) -> Vector3:
	var fwd := -cam.global_transform.basis.z
	var p := v.cross(fwd)
	if p.length_squared() < 0.0001:
		p = v.cross(Vector3.UP)
	return p.normalized()




func _star(im: ImmediateMesh, at: Vector3, r: float, color: Color) -> void:
	for v in [Vector3.RIGHT, Vector3.UP, Vector3(0.7, 0.7, 0.0), Vector3(-0.7, 0.7, 0.0)]:
		_line(im, at - v * r, at + v * r, color)


## Orthographic so the planes keep their parallel edges instead of foreshortening,
## and fitted to the screen *below the HUD bar* rather than to the whole viewport --
## fitting the full rect is what let the text sit on top of the board.
func _frame_camera() -> void:
	rig.rotation = Vector3(pitch, yaw, 0.0)
	var basis := rig.global_transform.basis
	var inv := basis.inverse()

	# Bounding box in the camera's own frame, not the average of the cells: averaging
	# pulls the centre toward wherever the cells happen to be dense and leaves the
	# board sitting off to one side.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in Board.total_cells(size):
		var v := inv * _world(Board.index_to_coords(i, size))
		lo = lo.min(v)
		hi = hi.max(v)
	lo -= Vector3(1.5, 1.5, 0.0)
	hi += Vector3(1.5, 1.5, 0.0)

	var extent := hi - lo
	var vp := get_viewport().get_visible_rect().size
	var bar := _hud_px()
	zoom = maxf(extent.y / maxf(0.4, (vp.y - bar) / vp.y), extent.x / vp.aspect())
	# Raising the pivot drops the board down the screen, clear of the HUD bar.
	var mid := (lo + hi) * 0.5
	rig.position = basis * Vector3(mid.x, mid.y + bar / vp.y * zoom * 0.5, mid.z)
	half_depth = extent.z * 0.5
	cam.position = Vector3(0.0, 0.0, _cam_dist())


## Perspective, so a stack of planes actually reads as receding. Orthographic gives a
## deck zero convergence: the offset between planes comes out as skew, not distance,
## which is what made the packed view look like sheared paper. `zoom` stays the world
## height being framed; this turns it into the distance that frames it.
func _cam_dist() -> float:
	return zoom * 0.5 / tan(deg_to_rad(cam.fov) * 0.5) + half_depth + 1.0


## Height the HUD text actually occupies, so the fit can keep the board out from
## under it rather than guessing a margin.
##
## Measures the two labels, not their container: `Rows` sits in a full-screen
## MarginContainer and is stretched to it, so asking the container gave ~850 px of
## "bar" on a 900 px window. That drove the fit to frame roughly twice the board and
## shoved the pivot most of a screen downward -- the board came out small and low in
## every screenshot, in orthographic just as much as in perspective.
func _hud_px() -> float:
	return status.size.y + menu.size.y + 48.0


## Tweens layout and camera together, so the deck visibly flattens out into a row
## rather than cutting between two pictures.
func _set_view(v: View) -> void:
	if view == v:
		return
	# Only FOCUS remembers where you left it. SPREAD is the flat reference view and
	# always returns to face-on: it is supposed to be the same picture every time, so
	# restoring a remembered angle there is more disorienting, not less.
	if view == View.FOCUS:
		parked[View.FOCUS] = Vector2(yaw, pitch)
	view = v
	var to_angle: Vector2 = parked.get(View.FOCUS, A_ISO) if v == View.FOCUS else A_FLAT
	# Rebase to the equivalent yaw nearest the target before interpolating. Orbiting
	# nine times round leaves yaw nine turns from where it started, and a plain lerp
	# to the stored angle then unwinds every one of them on screen.
	yaw = to_angle.x + wrapf(yaw - to_angle.x, -PI, PI)
	var from_angle := Vector2(yaw, pitch)
	var from_spread := spread
	var to_spread := 1.0 if v == View.SPREAD else 0.0
	var t := create_tween()
	t.tween_method(func(u: float):
			var a := from_angle.lerp(to_angle, u)
			yaw = a.x
			pitch = a.y
			_set_spread(lerpf(from_spread, to_spread, u)), 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_refresh_hud()


## Next board in SIZES, wrapping. Deals a fresh game, because changing the shape of
## the lattice invalidates every coordinate in the old one.
func _cycle_size() -> void:
	var i := SIZES.find(size)
	size = SIZES[(i + 1) % SIZES.size()] if i >= 0 else SIZES[0]
	new_game()


func _view_angle(v: View) -> Vector2:
	return A_FLAT if v == View.SPREAD else A_ISO


## Straight to a view with no tween. Used by the screenshot harness.
func snap_view(v: View) -> void:
	view = v
	var a := _view_angle(v)
	yaw = a.x
	pitch = a.y
	_set_spread(1.0 if v == View.SPREAD else 0.0)
	_refresh_hud()


func _set_spread(s: float) -> void:
	spread = s
	player.position = _world(coords)
	_draw_board()
	_frame_camera()
	_place_ghosts()


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
		g.get_node("Number").text = str(i + 1)
		ghosts.add_child(g)
	_place_ghosts()


## Markers follow the layout while the stack explodes, instead of hanging where the
## planes used to be.
func _place_ghosts() -> void:
	var kids := ghosts.get_children()
	for i in mini(kids.size(), moves.size()):
		kids[i].position = _world(moves[i]["coords"])


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
	var mode := "SPREAD" if view == View.SPREAD else "FOCUS"
	if roll == 0:
		status.text = "at %s  -  turn %d  -  SPACE to roll d%d" % [here, turns, die_faces()]
		menu.text = "%dD board %s  -  %d planes  -  %s view  -  TAB view, D dimensions, C recentre camera, R restart  -  drag to orbit, wheel to zoom" \
				% [size.size(), str(size), Board.plane_count(size), mode]
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
	# Which planes are lit changed the moment the move list emptied.
	_draw_board()
	await _hop(dest, 0.35, Tween.TRANS_BOUNCE)

	var idx := Board.coords_to_index(coords, size)
	if links.has(idx):
		await _slide_link(Board.index_to_coords(links[idx], size))

	# Landing somewhere new changes which plane is lit and which frame is warm.
	_draw_board()
	won = Board.dist_to_goal(coords, size) == 0
	busy = false
	_refresh_hud()


func _hop(dest: PackedInt32Array, secs: float, trans: Tween.TransitionType) -> void:
	if not anim:
		coords = dest
		player.position = _world(dest)
		return
	var t := create_tween()
	t.tween_property(player, "position", _world(dest), secs) \
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
		player.position = _world(dest)
		return
	var a := player.position
	var b := _world(dest)
	var mid := a.lerp(b, 0.5) + _perp(b - a) * (b - a).length() * 0.18
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
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(zoom * 1.1)
	elif event is InputEventMouseMotion and dragging:
		# Wrapped, so yaw never drifts to some large multiple of a turn away from the
		# angles it gets compared against.
		yaw = wrapf(yaw - event.relative.x * 0.006, -PI, PI)
		pitch = clampf(pitch - event.relative.y * 0.006, -1.4, 1.4)
		rig.rotation = Vector3(pitch, yaw, 0.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		# ponytail: R, TAB and the number keys read raw keycodes rather than adding
		# input actions to project.godot. "roll" reuses the built-in ui_accept.
		if event.keycode == KEY_R:
			new_game()
		elif event.keycode == KEY_TAB:
			_set_view(View.FOCUS if view == View.SPREAD else View.SPREAD)
		elif event.keycode == KEY_C:
			# Orbit is free, which means it is easy to end up looking at nothing.
			# C puts the camera back where the current view wants it, and forgets the
			# parked angle so the reset is not undone on the next trip through TAB.
			var a := _view_angle(view)
			yaw = a.x
			pitch = a.y
			parked.erase(view)
			_frame_camera()
		elif event.keycode == KEY_D:
			_cycle_size()
		elif busy or won:
			return
		elif event.is_action_pressed("ui_accept") and moves.is_empty():
			do_roll()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			choose(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			choose(9)


func _set_zoom(z: float) -> void:
	zoom = clampf(z, 3.0, 400.0)
	cam.position = Vector3(0.0, 0.0, _cam_dist())
