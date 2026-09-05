extends SceneTree

## Photographs a named game state, or all of them in one go.
##
## Every UI complaint this project has had needed a picture of a state that is a nuisance to reach by playing -- a fight mid-choice, a result waiting to be read, a cleared floor, a kit too big for the tray. Each one used to be a throwaway script written from scratch, which is how one of them ended up handing a 2D coordinate to a 3D board.
##
## Needs a real display and must run in the FOREGROUND: a backgrounded GUI run dies with exit 144.
##
##   DISPLAY=:0 godot --position -6000,-6000 --script tests/shots.gd -- fight-tell 10,10
##   DISPLAY=:0 godot --position -6000,-6000 --script tests/shots.gd -- all
##
## Writes shots/<state>.png. `all` writes every state and prints the list, which is the contact sheet: one run, every screen, eyeball them together after a change to any of them.

const Rules = preload("res://src/game/rules.gd")

const STATES := ["idle", "rolled", "fight-open", "fight-tell", "result-won", "result-lost",
		"cleared", "dead", "gifts", "big-kit", "glossary", "help"]

var m


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var want: String = args[0] if args.size() > 0 else "all"
	var board := _board(args[1] if args.size() > 1 else "10,10")

	var todo := STATES if want == "all" else [want]
	for state in todo:
		if not STATES.has(state):
			push_error("no such state: %s -- have %s" % [state, ", ".join(STATES)])
			quit(1)
			return
		await _shoot(state, board)
	print("wrote %d: %s" % [todo.size(), ", ".join(todo)])
	quit()


func _board(spec: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part in spec.split(","):
		out.append(part.to_int())
	return out


## A fresh scene per state, so nothing carries over from the last picture.
func _setup(board: PackedInt32Array) -> void:
	if m:
		m.free()
	m = load("res://src/main/main.tscn").instantiate()
	m.size = board
	root.add_child(m)
	await process_frame
	m.rng.seed = 7
	m.new_game()


func _kit(dice: Array) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for d in dice:
		out.append(d)
	return out


func _foe(faces: PackedInt32Array, games: Array, order: int, boss := false) -> Dictionary:
	var g: Array[int] = []
	for x in games:
		g.append(x)
	return {"faces": faces, "games": g, "trait": order, "boss": boss}


func _shoot(state: String, board: PackedInt32Array) -> void:
	await _setup(board)
	var pair := _kit([PackedInt32Array([1, 2, 3]), PackedInt32Array([1, 1, 5, 5])])

	match state:
		"idle":
			m.turns = 1
		"rolled":
			m.do_roll()
		"fight-open":
			m.kit = pair
			m._pick_die(1)
			m._start_fight(_foe(PackedInt32Array([2, 4, 5, 6]), [0], Rules.OPEN), 0)
		"fight-tell":
			m.kit = pair
			m._start_fight(_foe(PackedInt32Array([1, 3, 4]), [0, 1], Rules.TELL), 0)
			m._cycle_contest(1)
		"result-won":
			m.kit = pair
			m._start_fight(_foe(PackedInt32Array([1, 1]), [0], Rules.OPEN), 0)
			m._resolve()
		"result-lost":
			m.kit = _kit([PackedInt32Array([1, 2, 3])])
			m._start_fight(_foe(PackedInt32Array([6, 6]), [0], Rules.OPEN), 0)
			m._resolve()
		"cleared":
			m.kit = pair
			var boss := _foe(PackedInt32Array([2, 4, 5, 6]), [0, 1], Rules.OPEN, true)
			m._start_fight(boss, -1)
			m.fight["wins"] = 2
			m.fight["over"] = "CLEARED"
			m.fight["last"] = "BIGGER  5 v 2  WON"
		"dead":
			m.kit = []
			m.dead = true
			m.floors = 2
		"gifts":
			m.do_roll()
		"big-kit":
			var many := []
			for i in 11:
				many.append(PackedInt32Array([1, 2, i % 5 + 1]))
			m.kit = _kit(many)
			m._pick_die(9)
		"glossary":
			m.hud.toggle_glossary()
		"help":
			m.hud.toggle_help()

	m._refresh_hud()
	for _i in 12:
		await process_frame
	get_root().get_texture().get_image().save_png("shots/%s.png" % state)
