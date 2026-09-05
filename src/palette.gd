extends RefCounted

## Every color the game draws, in one place. Nothing picks a color at a call site --
## a new palette should be an edit to this file and nothing else.
##
## Flat color, nothing over 1.0. The environment does no glow and no filmic tonemap,
## so what is written here is what lands on screen; separation comes from brightness
## against black, the way it does in every one of the reference plates. The board is
## a dim violet -> teal gradient that reads as one receding surface, and anything
## playable sits near full brightness on top of it.
##
## Colors authored into main.tscn (the black background, the HUD font colors) stay in
## the scene: scenes are authored by hand here, not built in _ready().

## The board itself: a gradient from the start cell's plane to the goal's, plus the
## frame around every plane.
const C_SHELL_START := Color(0.26, 0.10, 0.38)
const C_SHELL_GOAL := Color(0.09, 0.34, 0.40)
const C_FRAME := Color(0.17, 0.17, 0.26)
## Warm, so the plane you are standing on never reads as another board line.
const C_HERE := Color(0.78, 0.46, 0.13)

## What a cell does to you. These do double duty: they color the links drawn across
## the board, and they tint the numbered marker of any move that lands on one, so the
## number tells you where it goes before you commit to it.
const C_LADDER := Color(0.49, 1.0, 0.31)
const C_SNAKE := Color(1.0, 0.24, 0.60)
## The goal. Hot amber-gold rather than the pale yellow this was: on a board of
## violet, teal and acid green, a washed-out yellow read as another dim line instead
## of as the thing you are trying to reach.
const C_GOAL := Color(1.0, 0.72, 0.05)
## A move that lands on plain floor. Matches the marker color authored in ghost.tscn,
## and the dice on the tray: the same cyan says "this is yours to act with".
const C_MOVE := Color(0.35, 0.92, 1.0)
## Ink on a die's face. Near-black, because the face it sits on is at full brightness
## and a bright number on a bright die is not a number at all.
const C_DIE_INK := Color(0.03, 0.07, 0.10)

## Debug gizmo, one per lattice axis in AXIS_NAMES order: X Y Z W V U.
const C_AXIS := [
	Color(1.0, 0.28, 0.28),
	Color(0.35, 1.0, 0.35),
	Color(0.40, 0.58, 1.0),
	Color(1.0, 0.85, 0.20),
	Color(1.0, 0.40, 1.0),
	Color(0.35, 1.0, 1.0),
]
## Camera rotation rings, labelled in the world rather than printed as numbers.
const C_YAW := Color(1.0, 0.55, 0.15)
const C_PITCH := Color(0.70, 0.45, 1.0)
const C_ROLL := Color(0.85, 0.85, 0.85)


## Color for a `Rules.landing()` kind. The mapping lives here rather than at the
## marker, so a new palette does not have to be chased across the view scripts.
static func landing_color(kind: String) -> Color:
	match kind:
		"GOAL":
			return C_GOAL
		"LADDER":
			return C_LADDER
		"SNAKE":
			return C_SNAKE
	return C_MOVE
