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
const Pal = preload("res://src/palette.gd")

@onready var status: RichTextLabel = $Margin/Rows/Status
@onready var help: VBoxContainer = $Margin/Rows/Help
@onready var board_line: Label = $Margin/Rows/Help/Board
@onready var menu: Label = $Margin/Rows/Help/Moves

## Ink for reversed-out text. Near-black, because it sits on a full-brightness swatch and a bright glyph on a bright ground is not a glyph.
const INK := Color(0.04, 0.05, 0.07)

var last := {}


## `s` carries the whole turn: coords, size, links, moves, roll, turns, won, kit, die_index, rerolls, foes, fight, dead, roamer, floors, notice, mode.
func refresh(s: Dictionary) -> void:
	last = s
	_status(s)
	board_line.text = "%dD board %s  -  %d planes  -  %s view  -  %s" \
			% [s["size"].size(), str(s["size"]), Board.plane_count(s["size"]), s["mode"], _kit(s)]
	menu.text = _moves(s)


## Reversed out: the swatch is the highlight, not the capitals. `Status` is a RichTextLabel for exactly this -- a Label can only colour the whole of itself, and "the word is in capitals" is not a highlight, it is shouting.
func _hi(text: String, bg: Color) -> String:
	return "[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]" \
			% [bg.to_html(false), INK.to_html(false), text]


func _tint(text: String, c: Color) -> String:
	return "[color=#%s]%s[/color]" % [c.to_html(false), text]


func _status(s: Dictionary) -> void:
	if s["dead"]:
		status.text = _hi("RUN OVER", Pal.C_SNAKE) + "  %d floors cleared  -  SHIFT+R restart" % s["floors"]
		return
	if s["won"]:
		status.text = _hi("WIN", Pal.C_GOAL) + "  in %d turns  -  SHIFT+R restart" % s["turns"]
		return
	if not s["fight"].is_empty():
		status.text = _fight(s["fight"], s)
		return
	var here := "(%s)" % ", ".join(Array(s["coords"]).map(func(v): return str(v)))
	# How far the chaser has to walk to reach you. A number rather than something to read off the board, because in a projected 4D view nobody can count that by eye -- and a clock you cannot read is an ambush.
	var chase := ""
	if not s["roamer"].is_empty():
		chase = "  -  " + _tint("chaser %d" % Board.manhattan(s["coords"], s["roamer"]), Pal.C_FOE)
	# The die, the roll and the spares are all objects on the tray now, so the line says only what the tray cannot: where you are, and what the board wants next.
	if s["roll"] == 0:
		# No turn count and no ESC prompt past the first turn: the run's score is floors cleared, the win line reports the turns, and a prompt you have already read is noise sitting where the next real thing has to go.
		var esc := "  -  ESC help" if s["turns"] == 0 else ""
		status.text = "%s  -  floor %dD%s  -  SPACE to roll%s%s" \
				% [here, s["size"].size(), chase, esc, _note(s)]
		return
	if s["moves"].is_empty():
		status.text = "%s  -  nothing legal from here%s%s%s" % [here, chase, _spare(s), _note(s)]
		return
	status.text = "%s  -  pick a marker%s%s%s" % [here, chase, _spare(s), _note(s)]


## The one line a fight needs: who is across the table, what is being contested, and which half of the choice is yours. The dice themselves are on the tray -- yours in the near corner, the foe's in the far one -- so this says nothing they already show.
func _fight(f: Dictionary, s: Dictionary) -> String:
	var mine: String = Rules.die_name(s["kit"][s["die_index"]])
	# A settled fight waits to be read, and says what the next press is about to do rather than making you work it out from the tray afterwards.
	if f["over"] == "CLEARED":
		return _hi("FLOOR CLEARED", Pal.C_GOAL) \
				+ "  the boss is beaten  -  SPACE to climb to %dD" % (s["size"].size() + 1)
	if f["over"] == "WON":
		return _hi("YOU WON", Pal.C_LADDER) + "  %s  -  SPACE takes their %s" \
				% [f["last"], Rules.die_name(f["foe"]["faces"])]
	if f["over"] == "LOST":
		var cost := "%s is taken" % mine
		if s["kit"].size() == 1:
			cost = "your last die shatters" if s["kit"][0].size() <= Rules.MIN_FACES \
					else "your last die cracks"
		return _hi("YOU LOST", Pal.C_SNAKE) + "  %s  -  SPACE, %s" % [f["last"], cost]
	if f["discard"]:
		return _hi("KIT FULL", Pal.C_GOAL) + "  LEFT/RIGHT choose, SPACE drops %s%s" \
				% [_hi(mine, Pal.C_MOVE), _note(s)]
	var foe: Dictionary = f["foe"]
	var head: String = _hi("BOSS  %d-%d of 3" % [f["wins"], f["losses"]], Pal.C_GOAL) \
			if foe["boss"] else _hi("FIGHT", Pal.C_FOE)
	var last: String = "  -  %s" % f["last"] if not f["last"].is_empty() else ""
	# The matchup, always: your die, their die, and the contest holding them. A line that says "vs 1355" and stops has left out the half of it that is yours.
	var matchup := "  %s vs %s" % [_hi(mine, Pal.C_MOVE), _hi(Rules.die_name(foe["faces"]), Pal.C_FOE)]
	if f["game"] < 0:
		# TELL: its die is on the table and the contest is yours to name. The one you are about to commit to is reversed out; the rest are just text.
		var left := []
		for g in foe["games"]:
			if not f["used"].has(g):
				left.append(g)
		var parts := PackedStringArray()
		for i in left.size():
			var label: String = MG.ALL[left[i]].label()
			parts.append(_hi(label, Pal.C_MOVE) if i == f["pick"] else " %s " % label)
		return "%s%s%s  -  UP/DOWN pick the contest, SPACE commits:  %s%s" \
				% [head, matchup, last, "  ".join(parts), _note(s)]
	return "%s%s under %s%s  -  LEFT/RIGHT change die, SPACE stakes%s" \
			% [head, matchup, _hi(MG.ALL[f["game"]].label(), Pal.C_FOE), last, _note(s)]


## What just happened, or what the die you just picked up actually is. Carried until the next roll: a fight that ends in silence leaves you looking at a tray with one fewer die on it, and a die whose faces you cannot read is a die you cannot choose with.
func _note(s: Dictionary) -> String:
	return "" if s["notice"].is_empty() else "\n%s" % _tint(s["notice"], Pal.C_MOVE)


## The token is spent with the same key that rolls, so the line says so rather than naming a key nobody would guess.
func _spare(s: Dictionary) -> String:
	return "  -  SPACE rerolls (%d)" % s["rerolls"] if s["rerolls"] > 0 else ""


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
