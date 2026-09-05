extends CanvasLayer

## The text. Handed a snapshot of the turn and formats it -- it reads game state and
## never changes any.
##
## One line stays on the play screen. Everything else -- the move list, the legend, the
## controls -- lives behind ESC, because the board is supposed to say what the moves
## are: the markers are numbered, tinted and shaped for exactly that.

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")
const MG = preload("res://src/game/minigames.gd")

@onready var status: Label = $Margin/Rows/Status
@onready var help: VBoxContainer = $Margin/Rows/Help
@onready var board_line: Label = $Margin/Rows/Help/Board
@onready var menu: Label = $Margin/Rows/Help/Moves

var last := {}


## `s` carries the whole turn: coords, size, links, moves, roll, turns, won, faces,
## kit, die_index, rerolls, mode.
func refresh(s: Dictionary) -> void:
	last = s
	_status(s)
	board_line.text = "%dD board %s  -  %d planes  -  %s view  -  %s" \
			% [s["size"].size(), str(s["size"]), Board.plane_count(s["size"]), s["mode"], _kit(s)]
	menu.text = _moves(s)


func _status(s: Dictionary) -> void:
	if s["dead"]:
		status.text = "RUN OVER  -  no dice left  -  SHIFT+R restart"
		return
	if s["won"]:
		status.text = "WIN in %d turns  -  SHIFT+R restart" % s["turns"]
		return
	if not s["fight"].is_empty():
		status.text = _fight(s["fight"])
		return
	var here := "(%s)" % ", ".join(Array(s["coords"]).map(func(v): return str(v)))
	# The die, the roll and the spares are all objects on the tray now, so the line
	# says only what the tray cannot: where you are, and what the board wants next.
	if s["roll"] == 0:
		status.text = "%s  -  turn %d  -  SPACE to roll  -  ESC help" % [here, s["turns"]]
		return
	if s["moves"].is_empty():
		status.text = "%s  -  nothing legal from here" % here
		return
	status.text = "%s  -  pick a marker" % here


## The one line a fight needs: who is across the table, what is being contested, and which half of the choice is yours. The dice themselves are on the tray -- yours in the near corner, the foe's in the far one -- so this says nothing they already show.
func _fight(f: Dictionary) -> String:
	if f["discard"]:
		return "KIT FULL  -  press a number to drop a die"
	var foe: Dictionary = f["foe"]
	var head := "BOSS %d-%d" % [f["wins"], f["losses"]] if foe["boss"] else "FOE"
	var last: String = "  -  %s" % f["last"] if not f["last"].is_empty() else ""
	if f["game"] < 0:
		# TELL: its die is on the table and the contest is yours to name.
		var parts := PackedStringArray()
		var i := 1
		for g in foe["games"]:
			if not f["used"].has(g):
				parts.append("[%d] %s" % [i, MG.ALL[g].label()])
				i += 1
		return "%s  -  pick the contest  %s%s" % [head, "  ".join(parts), last]
	return "%s  -  %s  -  SPACE stakes the die you picked%s" \
			% [head, MG.ALL[f["game"]].label(), last]


func _moves(s: Dictionary) -> String:
	var moves: Array = s["moves"]
	if moves.is_empty():
		return "no move on the board"
	var lines := PackedStringArray()
	for i in moves.size():
		lines.append("%d)  %s" % [i + 1, _move_label(moves[i], s["size"], s["links"], s["foes"])])
	return "\n".join(lines)


## The kit, with the selected die marked. The number keys pick between them while no
## markers are up, which is the same key doing the other half of its job.
func _kit(s: Dictionary) -> String:
	var kit: Array[PackedInt32Array] = s["kit"]
	var parts := PackedStringArray()
	for i in kit.size():
		parts.append("[%d] %s%s" % [i + 1, Rules.die_name(kit[i]), " <" if i == s["die_index"] else ""])
	return "die  " + "  ".join(parts)


func _move_label(m: Dictionary, size: PackedInt32Array, links: Dictionary, foes: Dictionary) -> String:
	var sign_char := "+" if m["dir"] > 0 else "-"
	var axis: int = m["axis"]
	var axis_name := Board.AXIS_NAMES[axis] if axis < Board.AXIS_NAMES.length() else str(axis)
	var kind := Rules.landing(m["coords"], size, links, foes)
	return "%s%s -> (%s)%s" % [sign_char, axis_name,
			", ".join(Array(m["coords"]).map(func(v): return str(v))),
			"" if kind.is_empty() else "  " + kind]


## Fades rather than cuts: a panel that appears between frames reads as a glitch the
## same way a camera jump does.
func toggle_help() -> void:
	var opening := not help.visible
	if opening:
		help.modulate.a = 0.0
		help.visible = true
	var t := create_tween()
	t.tween_property(help, "modulate:a", 1.0 if opening else 0.0, 0.15)
	if not opening:
		t.tween_callback(func(): help.visible = false)


## Height the text actually occupies, so the camera fit can keep the board out from
## under it rather than guessing a margin. The overlay is not counted: it is a panel
## you opened over the board, not a permanent bar the board has to live below.
##
## Measures the label, not its container: `Rows` sits in a full-screen MarginContainer
## and is stretched to it, so asking the container gave ~850 px of "bar" on a 900 px
## window. That drove the fit to frame roughly twice the board and shoved the pivot
## most of a screen downward.
func bar_px() -> float:
	return status.size.y + 48.0
