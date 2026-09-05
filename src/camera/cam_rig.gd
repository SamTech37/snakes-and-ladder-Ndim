extends Node3D

## The camera: a free orbit on an Euler rig, plus the fit that frames the board.
## Owns every number that describes where the camera is -- yaw, pitch, zoom, pan --
## so nothing else has to reach into `rotation` to find out.

## FOCUS looks at the cube nearly square-on with just enough turn to see that the
## slices are separated in depth. 45 degrees of yaw and 35 of pitch -- a true
## isometric corner -- was in here for no reason I ever justified, and it renders
## every plane as a leaning parallelogram: seen from a corner, a cube has no square
## face pointing at you.
const A_ISO := Vector2(0.30, -0.16)
const A_FLAT := Vector2(0.0, 0.0)

@onready var cam: Camera3D = $Camera3D

## Wired by main. The fit needs the cells' world positions, and the fit has to keep
## the board out from under the HUD text rather than guessing a margin.
var board: Node3D
var hud: CanvasLayer

## Orbit stays free: every fixed view is a subset of it, and without it there is no
## way to judge which angles are worth fixing on.
var yaw := A_ISO.x
var pitch := A_ISO.y
var zoom := 20.0

## Right-drag offset, in the camera's own screen plane and in world units. The fit
## frames the whole board, so on a big lattice zoomed in there is no way to reach the
## corner you are playing in without it. Added on top of the fitted pivot rather than
## replacing it, so it survives a refit; C clears it.
var pan := Vector2.ZERO

## Half the board's depth along the view axis, so the camera can be pulled back clear
## of the nearest plane rather than starting inside the stack.
var half_depth := 0.0


## Frames the board *below the HUD bar* rather than in the whole viewport -- fitting
## the full rect is what let the text sit on top of the board.
func fit() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	var b := global_transform.basis
	var inv := b.inverse()

	# Bounding box in the camera's own frame, not the average of the cells: averaging
	# pulls the centre toward wherever the cells happen to be dense and leaves the
	# board sitting off to one side.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in board.cell_count():
		var v: Vector3 = inv * board.world(board.cell(i))
		lo = lo.min(v)
		hi = hi.max(v)
	lo -= Vector3(1.5, 1.5, 0.0)
	hi += Vector3(1.5, 1.5, 0.0)

	var extent := hi - lo
	var vp := get_viewport().get_visible_rect().size
	var bar: float = hud.bar_px()
	zoom = maxf(extent.y / maxf(0.4, (vp.y - bar) / vp.y), extent.x / vp.aspect())
	# Raising the pivot drops the board down the screen, clear of the HUD bar.
	var mid := (lo + hi) * 0.5
	position = b * Vector3(mid.x + pan.x, mid.y + bar / vp.y * zoom * 0.5 + pan.y, mid.z)
	half_depth = extent.z * 0.5
	cam.position = Vector3(0.0, 0.0, _cam_dist())


## Perspective, so a stack of planes actually reads as receding. Orthographic gives a
## deck zero convergence: the offset between planes comes out as skew, not distance,
## which is what made the packed view look like sheared paper. `zoom` stays the world
## height being framed; this turns it into the distance that frames it.
func _cam_dist() -> float:
	return zoom * 0.5 / tan(deg_to_rad(cam.fov) * 0.5) + half_depth + 1.0


func set_zoom(z: float) -> void:
	zoom = clampf(z, 3.0, 400.0)
	cam.position = Vector3(0.0, 0.0, _cam_dist())


## Left-drag. Both angles wrapped, never clamped, so neither drifts to some large
## multiple of a turn away from the angles it gets compared against. Pitch used to
## stop just short of overhead; past vertical the view is upside down and horizontal
## drag reverses, which is what a free orbit on an Euler rig does.
func orbit(rel: Vector2) -> void:
	yaw = wrapf(yaw - rel.x * 0.006, -PI, PI)
	pitch = wrapf(pitch - rel.y * 0.006, -PI, PI)
	rotation = Vector3(pitch, yaw, 0.0)
	board.on_camera_moved()


## Right-drag: the board follows the cursor. Scaled by the framed world height per
## pixel, so a drag moves the same distance under the cursor at every zoom. Moves the
## rig directly rather than refitting, which would throw the wheel zoom away on every
## mouse move.
func pan_by(rel: Vector2) -> void:
	var k := zoom / get_viewport().get_visible_rect().size.y
	var d := Vector2(-rel.x * k, rel.y * k)
	pan += d
	position += global_transform.basis * Vector3(d.x, d.y, 0.0)


## Rebases `yaw`/`pitch` to the equivalent angles nearest `to`. Orbiting nine times
## round leaves yaw nine turns from where it started, and a plain lerp to a stored
## angle then unwinds every one of them on screen.
func rebase(to: Vector2) -> void:
	yaw = to.x + wrapf(yaw - to.x, -PI, PI)
	pitch = to.y + wrapf(pitch - to.y, -PI, PI)


## Flies the camera to an angle instead of snapping to it, and brings the pan home
## with it. Nothing that moves the camera should cut: an instant jump costs the player
## their bearings and reads as a glitch rather than a move.
func fly_to(to: Vector2, secs := 0.45) -> void:
	rebase(to)
	var from := Vector2(yaw, pitch)
	var from_pan := pan
	var t := create_tween()
	t.tween_method(func(u: float):
			var a := from.lerp(to, u)
			yaw = a.x
			pitch = a.y
			pan = from_pan.lerp(Vector2.ZERO, u)
			fit()
			board.on_camera_moved(), 0.0, 1.0, secs) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Perpendicular to `v` across the screen. Taken against the camera's forward vector
## rather than a fixed axis: the planes are tilted in 3D, so a chevron built in the xy
## plane would collapse to nothing at most orbit angles.
func perp(v: Vector3) -> Vector3:
	var fwd := -cam.global_transform.basis.z
	var p := v.cross(fwd)
	if p.length_squared() < 0.0001:
		p = v.cross(Vector3.UP)
	return p.normalized()
