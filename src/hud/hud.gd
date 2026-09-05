extends CanvasLayer

## The text. Handed a snapshot of the turn and formats it -- it reads game state and
## never changes any.

const Board = preload("res://src/board/board.gd")
const Rules = preload("res://src/game/rules.gd")

@onready var status: Label = $Margin/Rows/Status
@onready var menu: Label = $Margin/Rows/Moves


## `s` carries the whole turn: coords, size, links, moves, roll, turns, won, faces,
## planes, mode.
func refresh(s: Dictionary) -> void:
	if s["won"]:
		status.text = "WIN in %d turns  -  R to restart" % s["turns"]
		menu.text = ""
		return
	var here := "(%s)" % ", ".join(Array(s["coords"]).map(func(v): return str(v)))
	if s["roll"] == 0:
		status.text = "at %s  -  turn %d  -  SPACE to roll d%d" % [here, s["turns"], s["faces"]]
		menu.text = "%dD board %s  -  %d planes  -  %s view  -  TAB view, D dimensions, C recentre, F3 debug, R restart  -  drag to orbit, right-drag to pan, wheel to zoom" \
				% [s["size"].size(), str(s["size"]), Board.plane_count(s["size"]), s["mode"]]
		return
	status.text = "rolled %d  -  at %s  -  turn %d" % [s["roll"], here, s["turns"]]
	var moves: Array = s["moves"]
	if moves.is_empty():
		menu.text = "no legal move, turn forfeit  -  SPACE to roll again"
		return
	var lines := PackedStringArray()
	for i in moves.size():
		lines.append("%d)  %s" % [i + 1, _move_label(moves[i], s["size"], s["links"])])
	menu.text = "\n".join(lines)


func _move_label(m: Dictionary, size: PackedInt32Array, links: Dictionary) -> String:
	var sign_char := "+" if m["dir"] > 0 else "-"
	var axis: int = m["axis"]
	var axis_name := Board.AXIS_NAMES[axis] if axis < Board.AXIS_NAMES.length() else str(axis)
	var kind := Rules.landing(m["coords"], size, links)
	return "%s%s -> (%s)%s" % [sign_char, axis_name,
			", ".join(Array(m["coords"]).map(func(v): return str(v))),
			"" if kind.is_empty() else "  " + kind]


## Height the text actually occupies, so the camera fit can keep the board out from
## under it rather than guessing a margin.
##
## Measures the two labels, not their container: `Rows` sits in a full-screen
## MarginContainer and is stretched to it, so asking the container gave ~850 px of
## "bar" on a 900 px window. That drove the fit to frame roughly twice the board and
## shoved the pivot most of a screen downward -- the board came out small and low in
## every screenshot, in orthographic just as much as in perspective.
func bar_px() -> float:
	return status.size.y + menu.size.y + 48.0
