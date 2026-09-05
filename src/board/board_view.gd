extends Node3D

## Everything the board looks like: the plane grids and frames, the goal star, the
## links, and the F3 gizmo. Geometry only -- it is handed the game state and draws it,
## and never decides anything about a turn.
##
## The nodes it fills (Grid, Shafts, Heads, Dots, DebugLabels) are its children in
## main.tscn; it authors none of them.

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")
## Every color comes from here. Don't write a Color() literal in this file.
const Pal = preload("res://src/palette.gd")
const LABEL_FONT = preload("res://src/main/mono.tres")

## What a plane that is neither yours nor a destination drops to. Dimmed, not hidden:
## the stack has to stay visible or FOCUS stops being a view of the board.
const DIM := 0.22

## Length of the cone at the destination end of a link.
const HEAD_LEN := 0.7

@onready var grid: MeshInstance3D = $Grid
@onready var shafts: MultiMeshInstance3D = $Shafts
@onready var heads: MultiMeshInstance3D = $Heads
@onready var dots: MultiMeshInstance3D = $Dots
@onready var labels: Node3D = $DebugLabels

## Wired by main: the gizmo's rings are built around the camera.
var rig: Node3D

var size := PackedInt32Array([6, 6, 6])

## 0 = planes stacked like a deck, 1 = pulled apart into one row. Tweened by TAB, so
## the stack visibly explodes instead of cutting between two layouts.
var spread := 0.0

## SPREAD lights every plane: once they are pulled apart nothing hides behind
## anything, so nothing needs dimming.
var flat := false

## F3 axis gizmo.
var debug := false

## Last game state handed over, so a redraw driven by the spread tween or an orbit
## does not need the turn loop to pass it all again.
var coords := PackedInt32Array()
var links := {}
var moves := []


func world(c: PackedInt32Array) -> Vector3:
	return Board.coords_to_world(c, size, spread)


func cell(i: int) -> PackedInt32Array:
	return Board.index_to_coords(i, size)


func cell_count() -> int:
	return Board.total_cells(size)


## Takes the turn's state and redraws. The only entry point the turn loop needs.
func sync(c: PackedInt32Array, l: Dictionary, m: Array) -> void:
	coords = c
	links = l
	moves = m
	redraw()


## The gizmo's pitch and roll rings are built around the camera, so they have to be
## rebuilt as it turns -- but only while the gizmo is up.
func on_camera_moved() -> void:
	if debug:
		redraw()


## Planes the player can see into: the one being stood on, plus wherever this turn's
## legal moves land. Everything else draws at DIM.
func lit_planes() -> Dictionary:
	var lit := {Board.plane_of(coords, size): true}
	for m in moves:
		lit[Board.plane_of(m["coords"], size)] = true
	return lit


## Fills the Grid node's ImmediateMesh. Colors come from vertex color; the material is
## on the node, set in the scene. In FOCUS the planes you are not on are dimmed rather
## than dropped -- the stack has to stay there or it stops being a view of the board.
func redraw() -> void:
	var im: ImmediateMesh = grid.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var span := maxi(1, Board.dist_to_goal(cell(0), size))
	var here := Board.plane_of(coords, size)
	var lit := lit_planes()

	for i in cell_count():
		var c := cell(i)
		var f := _fade(Board.plane_of(c, size), lit)
		# Only axes 0 and 1 run inside a plane; a step along any higher axis leaves
		# for another plane and is not drawn as an edge.
		for k in mini(2, size.size()):
			if c[k] + 1 >= size[k]:
				continue
			var d := c.duplicate()
			d[k] += 1
			_seg(im, world(c), _shell_color(c, span) * f, world(d), _shell_color(d, span) * f)

	for p in Board.plane_count(size):
		_plane_frame(im, p, (Pal.C_HERE if p == here else Pal.C_FRAME) * _fade(p, lit))

	_star(im, world(Board.goal_coords(size)), 0.45, Pal.C_GOAL)
	_preview_links(im)
	if debug:
		_draw_axes(im)
	else:
		_clear_labels()
	im.surface_end()
	_draw_links(lit)


## A move that lands on a link draws a line to where the link would drag you. The
## marker's color says a snake is there; this says which snake, which is the half the
## color cannot carry -- and it is drawn with the board, so it follows the spread
## tween without any work of its own.
func _preview_links(im: ImmediateMesh) -> void:
	for m in moves:
		var idx := Board.coords_to_index(m["coords"], size)
		if not links.has(idx):
			continue
		var kind := Rules.landing(m["coords"], size, links)
		# Dimmer than the link geometry it parallels: this is a hint about a move you
		# have not made, not another object on the board.
		_line(im, world(m["coords"]), world(cell(links[idx])), Pal.landing_color(kind) * 0.55)


## One labelled arrow per lattice axis, from the start cell along the direction a +1
## step on that axis actually moves, plus labelled rings for yaw, pitch and roll.
## Directions are taken from the projection rather than assumed, so they stay correct
## for W and V and all the way through the spread tween.
func _draw_axes(im: ImmediateMesh) -> void:
	_clear_labels()
	var base := cell(0)
	var origin := world(base)
	for k in size.size():
		if size[k] < 2:
			continue
		var one := base.duplicate()
		one[k] = 1
		var step := world(one) - origin
		if step.length() < 0.001:
			continue
		var dir := step.normalized()
		var color: Color = Pal.C_AXIS[k % Pal.C_AXIS.size()]
		var tip := origin + dir * 3.5
		_line(im, origin, tip, color)
		# Barbs, so the arrow still reads when the axis points at the camera.
		var side: Vector3 = rig.perp(dir) * 0.25
		_line(im, tip, tip - dir * 0.6 + side, color)
		_line(im, tip, tip - dir * 0.6 - side, color)
		# A tick per cell, so the axis is countable as well as directional.
		for i in range(1, mini(size[k], 7)):
			var at := origin + step * float(i)
			_line(im, at - side * 0.6, at + side * 0.6, color)
		_label(Board.AXIS_NAMES[k] if k < Board.AXIS_NAMES.length() else str(k), tip + dir * 0.6, color)

	# Which way the camera turns. A compact widget sharing the axis arrows' origin, so
	# orientation is something you look at rather than read. Sized off the board, not
	# the zoom: rings scaled to the viewport swallowed everything behind them.
	var b: Basis = rig.cam.global_transform.basis
	_ring(im, origin, Vector3.RIGHT, Vector3.BACK, 2.6, Pal.C_YAW, "YAW", 0.0)
	_ring(im, origin, b.y, -b.z, 2.2, Pal.C_PITCH, "PITCH", -0.9)
	_ring(im, origin, b.x, b.y, 1.8, Pal.C_ROLL, "ROLL", 0.9)


## Circle spanned by `u` and `v`, labelled at the point furthest to screen-right and
## lifted by `lift` so the three rings do not stack their labels on one another.
func _ring(im: ImmediateMesh, centre: Vector3, u: Vector3, v: Vector3, r: float,
		color: Color, ring_name: String, lift: float) -> void:
	var un := u.normalized()
	var vn := v.normalized()
	var prev := centre + un * r
	var best := prev
	var best_x := -INF
	for i in range(1, 49):
		var a := TAU * float(i) / 48.0
		var p := centre + (un * cos(a) + vn * sin(a)) * r
		_line(im, prev, p, color)
		prev = p
		var x: float = rig.cam.global_transform.basis.x.dot(p)
		if x > best_x:
			best_x = x
			best = p
	_label(ring_name, best + rig.cam.global_transform.basis.y * lift, color)


func _label(text: String, at: Vector3, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = LABEL_FONT
	l.font_size = 64
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.position = at
	labels.add_child(l)


func _clear_labels() -> void:
	for l in labels.get_children():
		labels.remove_child(l)
		l.free()


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
		var ca := cell(a)
		var cb := cell(links[a])
		var up := Board.dist_to_goal(cb, size) < Board.dist_to_goal(ca, size)
		var f := maxf(_fade(Board.plane_of(ca, size), lit), _fade(Board.plane_of(cb, size), lit))
		var color := (Pal.C_LADDER if up else Pal.C_SNAKE) * f
		var wa := world(ca)
		var wb := world(cb)
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


func _fade(p: int, lit: Dictionary) -> float:
	if flat or lit.has(p):
		return 1.0
	return DIM


## Violet at the start corner, teal at the goal: the gradient doubles as the progress bar.
func _shell_color(c: PackedInt32Array, span: int) -> Color:
	return Pal.C_SHELL_START.lerp(Pal.C_SHELL_GOAL, 1.0 - float(Board.dist_to_goal(c, size)) / span)


## Outline around one plane, drawn through the projection so it tilts and slides with
## the plane it belongs to. The player's own is warm -- that is what says which plane
## you are standing on when the stack is packed.
func _plane_frame(im: ImmediateMesh, p: int, color: Color) -> void:
	var w := (size[0] - 1) if size.size() > 0 else 0
	var h := (size[1] - 1) if size.size() > 1 else 0
	# The first cell of plane p, since index = c0 + c1*size0 + p*size0*size1.
	var seed_cell := cell(p * size[0] * (size[1] if size.size() > 1 else 1))
	var corners: Array[Vector3] = []
	for xy in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(w, h), Vector2i(0, h)]:
		var c := seed_cell.duplicate()
		c[0] = xy.x
		if c.size() > 1:
			c[1] = xy.y
		corners.append(world(c))
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


func _star(im: ImmediateMesh, at: Vector3, r: float, color: Color) -> void:
	for v in [Vector3.RIGHT, Vector3.UP, Vector3(0.7, 0.7, 0.0), Vector3(-0.7, 0.7, 0.0)]:
		_line(im, at - v * r, at + v * r, color)
