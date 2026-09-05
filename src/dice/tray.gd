extends Node3D

## The dice, as objects. Parented to the camera so they hold the bottom-left corner of
## the frame through any orbit or zoom.
##
## This exists because the kit was a line of text: two dice you could only find by
## reading the HUD, and a reroll that was an invisible counter spent with a key nobody
## would guess. Here the kit is two dice -- the picked one bright and forward, the
## other dim and back -- and a reroll is a spare die sitting beside them. Nothing to
## read: you pick a die by clicking it, and you spend a spare by clicking a spare.
##
## The dice are **wireframe bipyramids with one side per face**: a d5 is a five-sided
## diamond, a d3 a three-sided one. The silhouette carries the number, and see-through
## wireframe is what the rest of the board already is -- a solid box on a board made
## entirely of lines was the one lump of matter on screen.

const Pal = preload("res://src/palette.gd")
const Rules = preload("res://src/game/rules.gd")

## Distance in front of the camera. Fixed, so the tray keeps its size on screen no
## matter how far the fit pulls the camera back.
const DEPTH := 4.0

## How many spares can be shown at once. Past this the count is a number nobody counts
## anyway, and the row would run into the middle of the screen.
const MAX_SPARES := 5

## Clicks land within this many pixels of a die's centre.
const HIT_PX := 34.0

@onready var cam: Camera3D = get_parent()
## Filled in _ready(): two dice are authored and the rest are copies, the same way the spares are. There is no cap on the kit any more, so the tray cannot be a fixed pair of nodes.
var dice: Array[Node3D] = []
@onready var spares: Node3D = $Spares
## The foe's die, on the opposite corner of the frame, facing the kit. A fight is two dice looking at each other -- the same thing the tray already is, mirrored.
@onready var foe: MeshInstance3D = $Foe

var picked := 0
var spare_count := 0
var anim := true

## True while the die is mid-throw, so the idle spin keeps its hands off it.
var tumbling := false


func _ready() -> void:
	dice = [$Die0, $Die1]
	for i in range(dice.size(), Rules.TRAY_DICE):
		var extra: Node3D = $Die0.duplicate()
		add_child(extra)
		dice.append(extra)

	# One spare is authored; the rest are copies of it. Five hand-placed shapes in the
	# scene would say nothing the first one does not.
	var first: Node3D = spares.get_child(0)
	for i in range(1, MAX_SPARES):
		var s := first.duplicate()
		s.position = Vector3(0.17 * i, 0.0, 0.0)
		spares.add_child(s)
	for s in spares.get_children():
		s.mesh = _bipyramid(4, 0.05, 0.075)
		s.material_override = _mat(Pal.C_HERE)
		s.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


## A slow turn on the die you are about to throw. A wireframe solid only reads as a
## solid while it moves; parked dead still it is a flat badge.
func _process(delta: float) -> void:
	if not anim or tumbling:
		return
	var d: Node3D = dice[picked]
	if d.visible:
		d.rotation.y += delta * 0.7
	# The foe's die turns as well, and the other way. A wireframe solid only reads as a solid while it moves, and one side of a fight sitting dead still while the other turns reads as the fight being one-sided.
	if foe.visible:
		foe.rotation.y -= delta * 0.55


## Bottom-left of whatever the viewport is now, computed from the camera's own frustum
## rather than a position guessed once against one window size.
func _layout() -> void:
	var half_h := tan(deg_to_rad(cam.fov) * 0.5) * DEPTH
	var half_w := half_h * get_viewport().get_visible_rect().size.aspect()
	position = Vector3(-half_w + 0.42, -half_h + 0.32, -DEPTH)
	# Mirrored across the frame from the tray's own corner, so the two sides of a fight sit as far apart as the screen allows.
	foe.position.x = 2.0 * (half_w - 0.42)


## Shows the kit, and puts every face label back to the die's name -- a die that has been rolled and moved with is showing a number that has already been spent, and a spent number where a name should be is just a wrong label.
## A board with one die shows one die. Each entry is a die's list of face values, so the silhouette counts its *sides* and the label spells the faces.
func set_kit(kit: Array[PackedInt32Array], sel: int) -> void:
	picked = sel
	for i in dice.size():
		var d: Node3D = dice[i]
		d.visible = i < kit.size()
		if not d.visible:
			continue
		var on := i == picked
		d.position = Vector3(0.24 * i, 0.0, 0.05 if on else -0.04)
		d.scale = Vector3.ONE * (1.0 if on else 0.68)
		var c: Color = Pal.C_MOVE if on else Pal.C_MOVE * 0.45
		# One side per face, so the shape counts the die out for you.
		d.mesh = _bipyramid(kit[i].size(), 0.11, 0.16)
		d.material_override = _mat(c)
		if not on:
			d.rotation = Vector3.ZERO
		var face: Label3D = d.get_node("Face")
		face.text = Rules.die_name(kit[i])
		face.modulate = c


## Spare dice are the rerolls. The count is the number of objects on the tray.
func set_spares(n: int) -> void:
	spare_count = n
	var kids := spares.get_children()
	for i in kids.size():
		kids[i].visible = i < n


## Called when a roll traps the player and hands one over: the new spare arrives with a
## kick, so the way out announces itself at the moment it is needed.
func flash_spares() -> void:
	if not anim or spare_count <= 0:
		return
	var s: Node3D = spares.get_child(mini(spare_count, MAX_SPARES) - 1)
	s.scale = Vector3.ONE * 2.2
	var t := create_tween()
	t.tween_property(s, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Puts the foe's die on the far side of the frame. Its faces are spelled out, because a foe die is rarely plain 1..n and the number of sides alone would be a lie about it.
func set_foe(faces: PackedInt32Array) -> void:
	foe.visible = true
	foe.mesh = _bipyramid(faces.size(), 0.11, 0.16)
	foe.material_override = _mat(Pal.C_FOE)
	var face: Label3D = foe.get_node("Face")
	face.text = Rules.die_name(faces)
	face.modulate = Pal.C_FOE
	face.visible = true


func clear_foe() -> void:
	foe.visible = false


## The foe throws the same way you do. Same tumble, so neither side's roll reads as more authored than the other's.
func roll_foe(n: int) -> void:
	_throw(foe, n)


## The die turns over and comes up on a number. The result belongs on the die that was
## thrown, not floating over the player -- a number landing on the player's head reads
## as something being done *to* them.
func roll_to(n: int) -> void:
	_throw(dice[picked], n)


func _throw(d: Node3D, n: int) -> void:
	var face: Label3D = d.get_node("Face")
	if not anim:
		face.text = str(n)
		return
	face.visible = false
	tumbling = true
	var t := create_tween()
	t.tween_property(d, "rotation", d.rotation + Vector3(TAU * 2.0, TAU * 1.5, 0.0), 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
			tumbling = false
			face.text = str(n)
			face.visible = true)
	# A small kick on landing, so the number arrives with the die rather than after it.
	t.tween_property(d, "scale", Vector3.ONE * 1.25, 0.06)
	t.tween_property(d, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK)


## Which die is under a screen position, or -1. Distance in pixels rather than a
## collision shape: these are two boxes, and a physics body for each would be a whole
## subsystem to answer a question `unproject_position` already answers.
func die_at(pos: Vector2) -> int:
	for i in dice.size():
		var d: Node3D = dice[i]
		if d.visible and cam.unproject_position(d.global_position).distance_to(pos) < HIT_PX:
			return i
	return -1


func spare_at(pos: Vector2) -> bool:
	for s in spares.get_children():
		if s.visible and cam.unproject_position(s.global_position).distance_to(pos) < HIT_PX * 0.6:
			return true
	return false


## A wireframe diamond: two apexes over a ring of `sides` points. Lines only -- these
## sit on a board that is nothing but lines, and the reference plates in ideas/ are
## see-through wireframes rather than shaded solids.
func _bipyramid(sides: int, r: float, h: float) -> ImmediateMesh:
	var n := maxi(3, sides)
	var ring: Array[Vector3] = []
	for i in n:
		var a := TAU * float(i) / float(n)
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in n:
		var p := ring[i]
		var q := ring[(i + 1) % n]
		im.surface_add_vertex(p)
		im.surface_add_vertex(q)
		for apex in [Vector3(0.0, h, 0.0), Vector3(0.0, -h, 0.0)]:
			im.surface_add_vertex(p)
			im.surface_add_vertex(apex)
	im.surface_end()
	return im


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m
