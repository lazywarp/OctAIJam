extends Node2D
## A line of hint text placed in the level.

var text := ""


func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(-400, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 800, 22,
		Color(1, 1, 1, 0.75))
