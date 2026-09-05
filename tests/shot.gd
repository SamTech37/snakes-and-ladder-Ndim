extends SceneTree

## Renders main.tscn once and writes a PNG, so the board can be looked at without
## a human at the keyboard. Needs a real display: --headless uses the dummy
## rasterizer and hangs, so pass DISPLAY and let the window flash.
## Run: SNL_SEED=7 DISPLAY=:0 godot --script tests/shot.gd -- out.png 10,10,10 0.6,-0.9 roll
## Args, all optional: output path, board size, "yaw,pitch" in radians, and "roll"
## to take a turn first so the numbered move markers are in frame.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "shot.png"

	var m = load("res://src/main/main.tscn").instantiate()
	if args.size() > 1:
		var dims := PackedInt32Array()
		for part in args[1].split(","):
			dims.append(part.to_int())
		m.size = dims
	root.add_child(m)
	# ponytail: reuse the drag flag to stop the idle yaw spin — a screenshot taken
	# after a variable number of real-time frames would otherwise never repeat.
	m.dragging = true
	if args.size() > 2:
		var ang := args[2].split(",")
		m.yaw = ang[0].to_float()
		m.pitch = ang[1].to_float()
	if args.size() > 3 and args[3] == "roll":
		m.do_roll()

	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("wrote %s  %s  yaw=%.2f pitch=%.2f" % [out, str(m.size), m.yaw, m.pitch])
	quit()
