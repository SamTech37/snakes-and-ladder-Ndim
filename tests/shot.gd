extends SceneTree

## Renders main.tscn once and writes a PNG into shots/, so the board can be looked
## at without a human at the keyboard. Needs a real display: --headless uses the
## dummy rasterizer and hangs, so pass DISPLAY and let the window flash.
##
## Run: SNL_SEED=7 DISPLAY=:0 godot --script tests/shot.gd -- shots/a.png 6,6,6 1 roll
## Args, all optional: output path, board size, spread (0 stacked / 1 exploded), and
## "roll" to take a turn first so the numbered move markers are in frame. A fifth
## "yaw,pitch" argument overrides the default isometric angle. "debug" adds the axis
## gizmo, "help" opens the ESC overlay, "spares" puts rerolls on the tray.

func _initialize() -> void:
	_hide_window()
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "shots/shot.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())

	var m = load("res://src/main/main.tscn").instantiate()
	if args.size() > 1:
		var dims := PackedInt32Array()
		for part in args[1].split(","):
			dims.append(part.to_int())
		m.size = dims
	root.add_child(m)
	# add_child inside _initialize does not run _ready synchronously, so the scene's
	# @onready vars are still null for one frame. Rolling before this await spawned
	# no markers at all and printed three null-access errors.
	await process_frame

	m.view3d.debug = args.has("debug")
	if args.has("help"):
		m.hud.toggle_help()
	if args.has("spares"):
		m.rerolls = 3
		m._refresh_tray()
	if args.size() > 3 and args[3] == "roll":
		m.do_roll()
	# Straight to the end state of the view rather than waiting on the tween.
	m.snap_view(m.View.SPREAD if args.size() > 2 and args[2].to_float() > 0.5 else m.View.FOCUS)
	# Only a "yaw,pitch" pair, so the flag words can sit in the same position.
	if args.size() > 4 and args[4].contains(","):
		var ang := args[4].split(",")
		m.rig.yaw = ang[0].to_float()
		m.rig.pitch = ang[1].to_float()
		m.set_spread(m.view3d.spread)

	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("wrote %s  %s  %s  yaw=%.2f pitch=%.2f" % [
			out, str(m.size), "SPREAD" if m.view == m.View.SPREAD else "FOCUS", m.rig.yaw, m.rig.pitch])
	quit()


## A real display is unavoidable here -- --headless uses the dummy rasterizer and
## cannot render at all -- but the window does not have to land in front of whoever
## is using the machine. Parked off the desktop and refused focus.
static func _hide_window() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-6000, -6000))
