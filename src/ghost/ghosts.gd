extends Node3D

## The numbered move markers. Numbers, not mouse picking, because numbers keep working
## when 5D offers ten directions. Each marker is tinted with what it lands on, so the
## choice can be read off the board instead of only off the text.

const Rules = preload("res://src/game/rules.gd")
const Pal = preload("res://src/palette.gd")

@export var ghost_scene: PackedScene

## Wired by main: markers sit at board positions, so they follow the spread tween.
var board: Node3D

var moves := []

## One material per landing color, made once and shared by every marker using it.
var mats := {}


func show_moves(m: Array, links: Dictionary) -> void:
	clear()
	moves = m
	for i in moves.size():
		var g := ghost_scene.instantiate()
		g.get_node("Number").text = str(i + 1)
		var c := Pal.landing_color(Rules.landing(moves[i]["coords"], board.size, links))
		# The mesh and its material are sub-resources of ghost.tscn and every instance
		# shares them, so the tint has to be an override rather than a write.
		g.material_override = _mat(c)
		g.get_node("Number").modulate = c
		add_child(g)
	place()


## Markers follow the layout while the stack explodes, instead of hanging where the
## planes used to be.
func place() -> void:
	var kids := get_children()
	for i in mini(kids.size(), moves.size()):
		kids[i].position = board.world(moves[i]["coords"])


func clear() -> void:
	# free(), not queue_free(): deferred frees only collect at end of frame, so a
	# caller that takes many turns without yielding piles up every marker ever made.
	moves = []
	for g in get_children():
		remove_child(g)
		g.free()


func _mat(c: Color) -> StandardMaterial3D:
	if not mats.has(c):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		mats[c] = m
	return mats[c]
