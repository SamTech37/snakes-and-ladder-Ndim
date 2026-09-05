extends SceneTree

## Measures whether a cell can be told apart from every other cell on screen, by
## projecting every cell through the camera the game actually ships and counting how
## many land within a click radius of an unrelated cell.
##
## This is why the board is laid out as panels. The old projection mapped axes onto
## x/y/z and orbited a perspective camera over the result; measured on this harness
## it scored, at a click radius of 8 px in a 1152x648 viewport:
##
##     board [6,6,6]     medianNN  ambig%  worst  farpair
##     3D yaw.25 pitch-.35   12.71   25.0%      4       26
##     3D yaw.77 pitch-1.20  12.57   23.1%      2       15
##     3D yaw.79 pitch-.62   15.99   23.1%      5       38
##     flat panels           45.86    0.0%      0        0
##
##     board [10,10,10]
##     3D yaw.25 pitch-.35   13.34   18.8%      4       97
##     3D yaw.77 pitch-1.20  13.77   19.7%      4      101
##     3D yaw.79 pitch-.62   13.27   24.0%      7      182
##     flat panels           18.07    0.0%      0        0
##
## Roughly one cell in four shared its pixel with a cell that was not even adjacent
## ("farpair"), at every angle, and shrinking the board made it worse rather than
## better. ambig% must stay at 0.
##
## Run: DISPLAY=:0 godot --script tests/test_readable.gd -- 6,6,6

const Board = preload("res://src/board/board.gd")
const CLICK_PX := 8.0

var size := PackedInt32Array([6, 6, 6])


func _initialize() -> void:
	# Same as shot.gd: needs a real display, but keeps its window off the desktop.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-6000, -6000))

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		size = PackedInt32Array()
		for part in args[0].split(","):
			size.append(part.to_int())

	var m = load("res://src/main/main.tscn").instantiate()
	m.size = size
	root.add_child(m)
	await process_frame

	var n := Board.total_cells(size)
	print("\nboard %s  -  %d cells  -  viewport %s  -  click radius %d px"
			% [str(size), n, str(root.size), int(CLICK_PX)])
	print("%-24s %5s %8s %8s %8s %8s" % ["view / angle", "cells", "medianNN", "ambig%", "worst", "farpair"])

	# Only cells you can actually act on are measured. In FOCUS that is the lit
	# plane; the rest of the deck is dimmed background and is *meant* to overlap --
	# holding every cell in a packed deck apart is what forced the planes so far
	# apart that FOCUS and SPREAD stopped looking like different views at all.
	#
	# Orbit is free, so some angles will still line things up. This reports the whole
	# sweep and holds only the default isometric view to zero; which other angles are
	# acceptable is a judgement call, not something to assert.
	for s in [0.0, 1.0]:
		# Each view has its own resting angle -- isometric for the packed deck,
		# face-on for the flat row -- and that is the one held to zero.
		var home: Vector2 = m._view_angle(m.View.SPREAD if s > 0.5 else m.View.FOCUS)
		for angle in [home, Vector2(0.25, -0.35), Vector2(1.4, -0.2), Vector2(0.79, -1.2)]:
			m.rig.yaw = angle.x
			m.rig.pitch = angle.y
			m.set_spread(s)
			await process_frame
			var label := "%s %.2f,%.2f" % ["SPREAD" if s > 0.5 else "FOCUS ", angle.x, angle.y]
			var ambiguous := _report(label, _project(m, s), m)
			if angle == home:
				assert(ambiguous == 0, "%s: playable cells share a pixel at the view's own angle" % label)
	print("")
	m.free()
	quit()


## Screen position of every cell that is lit in the current view.
func _project(m: Node, s: float) -> PackedInt32Array:
	var lit: Dictionary = m.view3d.lit_planes()
	var keep := PackedInt32Array()
	for i in Board.total_cells(size):
		var c := Board.index_to_coords(i, size)
		if s > 0.5 or lit.has(Board.plane_of(c, size)):
			keep.append(i)
	return keep


## Nearest-neighbour distances, how many cells have a stranger inside the click
## radius, and how far apart in board space the colliding pairs actually are -- a
## collision between adjacent cells is harmless, one between distant cells is not.
## Returns the ambiguous-cell count so the caller can assert on it.
func _report(label: String, cells: PackedInt32Array, m: Node) -> int:
	# ponytail: O(n^2), which is 1e6 pairs on the 10^3 board and runs in about a
	# second. A grid hash would be the fix if a bigger board ever needs measuring.
	var cam: Camera3D = m.rig.cam
	var n := cells.size()
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		pts[i] = cam.unproject_position(m.view3d.world(Board.index_to_coords(cells[i], size)))

	var nearest := PackedFloat32Array()
	nearest.resize(n)
	var ambiguous := 0
	var worst := 0
	var far_pairs := 0

	for i in n:
		var best := INF
		var crowd := 0
		for j in n:
			if i == j:
				continue
			var d := pts[i].distance_to(pts[j])
			best = minf(best, d)
			if d < CLICK_PX:
				crowd += 1
				if Board.manhattan(Board.index_to_coords(cells[i], size), Board.index_to_coords(cells[j], size)) > 1:
					far_pairs += 1
		nearest[i] = best
		if crowd > 0:
			ambiguous += 1
		worst = maxi(worst, crowd)

	var sorted := Array(nearest)
	sorted.sort()
	print("%-24s %5d %8.2f %7.1f%% %8d %8d" % [
			label, n, sorted[n / 2], 100.0 * float(ambiguous) / float(n), worst, far_pairs / 2])
	return ambiguous
