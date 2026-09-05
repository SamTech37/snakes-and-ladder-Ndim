extends CanvasLayer

## The text. Handed a snapshot of the turn and formats it -- it reads game state and
## never changes any.
##
## One line stays on the play screen. Everything else -- the move list, the legend, the
## controls -- lives behind ESC, because the board is supposed to say what the moves
## are: the markers are numbered, tinted and shaped for exactly that.

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")

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
	if s["won"]:
		status.text = "WIN in %d turns  -  R restart" % s["turns"]
		return
	var here := "(%s)" % ", ".join(Array(s["coords"]).map(func(v): return str(v)))
	var tail := "" if s["rerolls"] == 0 else "  -  X reroll x%d" % s["rerolls"]
	if s["roll"] == 0:
		status.text = "%s  -  turn %d  -  SPACE roll d%d%s  -  ESC help" \
				% [here, s["turns"], s["faces"], tail]
		return
	if s["moves"].is_empty():
		status.text = "%s  -  rolled %d, nothing legal%s" % [here, s["roll"], tail]
		return
	status.text = "%s  -  rolled %d, pick a marker%s" % [here, s["roll"], tail]


func _moves(s: Dictionary) -> String:
	var moves: Array = s["moves"]
	if moves.is_empty():
		return "no move on the board"
	var lines := PackedStringArray()
	for i in moves.size():
		lines.append("%d)  %s" % [i + 1, _move_label(moves[i], s["size"], s["links"])])
	return "\n".join(lines)


## The kit, with the selected die marked. The number keys pick between them while no
## markers are up, which is the same key doing the other half of its job.
func _kit(s: Dictionary) -> String:
	var kit: PackedInt32Array = s["kit"]
	var parts := PackedStringArray()
	for i in kit.size():
		parts.append("[%d] d%d%s" % [i + 1, kit[i], " <" if i == s["die_index"] else ""])
	return "die  " + "  ".join(parts)


func _move_label(m: Dictionary, size: PackedInt32Array, links: Dictionary) -> String:
	var sign_char := "+" if m["dir"] > 0 else "-"
	var axis: int = m["axis"]
	var axis_name := Board.AXIS_NAMES[axis] if axis < Board.AXIS_NAMES.length() else str(axis)
	var kind := Rules.landing(m["coords"], size, links)
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
